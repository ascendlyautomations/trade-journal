/**
 * Apply messages.profile_post_id migration and verify DM share inserts.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createClient } from "@supabase/supabase-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")
const MIGRATION = "20260624110000_messages_profile_post_id.sql"

function loadEnv() {
  const text = fs.readFileSync(path.join(root, ".env.local"), "utf8")
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter((line) => line && !line.startsWith("#"))
      .map((line) => {
        const index = line.indexOf("=")
        return [line.slice(0, index), line.slice(index + 1)]
      })
  )
}

async function applyMigration(env, sql) {
  const ref = env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)/)?.[1]
  if (!ref) throw new Error("Could not parse project ref")
  if (env.SUPABASE_ACCESS_TOKEN) {
    const response = await fetch(
      `https://api.supabase.com/v1/projects/${ref}/database/query`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ query: sql }),
      }
    )
    const body = await response.text()
    if (!response.ok) throw new Error(`Management API ${response.status}: ${body}`)
    return
  }
  throw new Error("Need SUPABASE_ACCESS_TOKEN to apply migration")
}

async function main() {
  const env = loadEnv()
  const sql = fs.readFileSync(
    path.join(root, "supabase", "migrations", MIGRATION),
    "utf8"
  )
  const supabase = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY
  )

  try {
    await applyMigration(env, sql)
    console.log("[apply] ok")
  } catch (err) {
    console.log("[apply]", err.message)
  }

  await new Promise((r) => setTimeout(r, 2000))

  const { data: convoRows } = await supabase.from("conversations").select("id").limit(1)
  const { data: profilePosts } = await supabase
    .from("profile_posts")
    .select("id, user_id")
    .limit(1)
  const { data: tradePosts } = await supabase.from("posts").select("id, user_id").limit(1)

  const convo = convoRows?.[0]
  const profilePost = profilePosts?.[0]
  const tradePost = tradePosts?.[0]
  const senderId = profilePost?.user_id ?? tradePost?.user_id

  if (!convo || !senderId) {
    console.log("missing test data")
    return
  }

  const probes = []

  if (profilePost) {
    const payload = {
      conversation_id: convo.id,
      sender_id: senderId,
      type: "profile_post",
      profile_post_id: profilePost.id,
      content: "__dm_share_probe_profile__",
      channel: null,
    }
    const { data, error } = await supabase
      .from("messages")
      .insert(payload)
      .select("id, type, profile_post_id, post_id")
      .single()
    probes.push({
      label: "profile_post share",
      ok: !error,
      code: error?.code,
      message: error?.message,
      data,
    })
    if (data?.id) await supabase.from("messages").delete().eq("id", data.id)
  }

  if (tradePost) {
    const payload = {
      conversation_id: convo.id,
      sender_id: senderId,
      type: "post",
      post_id: tradePost.id,
      content: "__dm_share_probe_trade_feed__",
      channel: null,
    }
    const { data, error } = await supabase
      .from("messages")
      .insert(payload)
      .select("id, type, profile_post_id, post_id")
      .single()
    probes.push({
      label: "trade feed post share",
      ok: !error,
      code: error?.code,
      message: error?.message,
      data,
    })
    if (data?.id) await supabase.from("messages").delete().eq("id", data.id)
  }

  console.log(JSON.stringify(probes, null, 2))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
