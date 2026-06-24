/**
 * Apply profile_post_comments user_id -> profiles FK fix and verify PostgREST embeds.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createClient } from "@supabase/supabase-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")
const MIGRATION = "20260624100000_profile_post_comments_user_id_profiles_fkey.sql"
const INSERT_SELECT =
  "id, profile_post_id, user_id, content, created_at, profiles(username, avatar_url)"
const LOAD_SELECT = `${INSERT_SELECT}, parent_comment_id`

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
    return "management-api"
  }

  const dbUrl =
    env.DATABASE_URL ||
    (env.SUPABASE_DB_PASSWORD
      ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
      : null)

  if (!dbUrl) {
    throw new Error("Need SUPABASE_ACCESS_TOKEN or SUPABASE_DB_PASSWORD / DATABASE_URL")
  }

  const { Client } = await import("pg")
  const client = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } })
  await client.connect()
  try {
    await client.query(sql)
  } finally {
    await client.end()
  }
  return "postgres"
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

  console.log("[apply] migration:", MIGRATION)
  try {
    const via = await applyMigration(env, sql)
    console.log("[apply] ok via", via)
  } catch (err) {
    console.log("[apply] skipped or failed:", err.message)
  }

  // Allow PostgREST schema reload
  await new Promise((r) => setTimeout(r, 2000))

  const { data: posts } = await supabase
    .from("profile_posts")
    .select("id, user_id")
    .limit(1)
  if (!posts?.length) {
    console.log("[verify] no profile_posts to test")
    return
  }

  const postId = posts[0].id
  const userId = posts[0].user_id

  const loadBefore = await supabase
    .from("profile_post_comments")
    .select(LOAD_SELECT)
    .eq("profile_post_id", postId)
    .limit(1)
  console.log("[verify] load embed:", loadBefore.error?.code ?? "OK")

  const { data: top, error: topErr } = await supabase
    .from("profile_post_comments")
    .insert({
      profile_post_id: postId,
      user_id: userId,
      content: "__fk_fix_probe_top__",
    })
    .select(INSERT_SELECT)
    .single()
  console.log("[verify] insert top:", topErr?.code ?? "OK", top?.profiles?.username ?? null)

  let replyId = null
  if (top?.id) {
    const { data: reply, error: replyErr } = await supabase
      .from("profile_post_comments")
      .insert({
        profile_post_id: postId,
        user_id: userId,
        content: "__fk_fix_probe_reply__",
        parent_comment_id: top.id,
      })
      .select(LOAD_SELECT)
      .single()
    console.log(
      "[verify] insert reply:",
      replyErr?.code ?? "OK",
      reply?.parent_comment_id ?? null
    )
    replyId = reply?.id ?? null

    const ownerId = userId
    const { error: notifErr } = await supabase.from("notifications").insert({
      user_id: ownerId,
      sender_id: userId,
      type: "comment",
      profile_post_id: postId,
      content: "__fk_fix_probe_top__".slice(0, 200),
    })
    console.log("[verify] notification:", notifErr?.code ?? "OK")

    if (notifErr?.code) {
      await supabase
        .from("notifications")
        .delete()
        .eq("type", "comment")
        .eq("sender_id", userId)
        .eq("profile_post_id", postId)
        .eq("content", "__fk_fix_probe_top__".slice(0, 200))
    }
  }

  const { count: likeCount } = await supabase
    .from("profile_post_likes")
    .select("id", { count: "exact", head: true })
    .eq("profile_post_id", postId)
  console.log("[verify] likes table readable, count:", likeCount ?? 0)

  if (replyId) {
    await supabase.from("profile_post_comments").delete().eq("id", replyId)
  }
  if (top?.id) {
    await supabase.from("profile_post_comments").delete().eq("id", top.id)
  }

  const failed = [loadBefore.error, topErr].some((e) => e?.code === "PGRST200")
  if (failed) process.exit(1)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
