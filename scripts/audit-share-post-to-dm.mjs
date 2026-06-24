/**
 * Read-only audit: share post to DM insert failure.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    env[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return env
}

const env = loadEnv()
const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)

const POST_PAYLOAD_SHAPE = {
  type: "post",
  content: "__share_audit_probe__",
  channel: null,
}

async function probeInsert(label, payload) {
  const { data, error } = await supabase
    .from("messages")
    .insert(payload)
    .select("id, created_at")
    .single()

  const result = {
    label,
    ok: !error,
    code: error?.code ?? null,
    message: error?.message ?? null,
    details: error?.details ?? null,
    hint: error?.hint ?? null,
    id: data?.id ?? null,
  }

  if (data?.id) {
    await supabase.from("messages").delete().eq("id", data.id)
  }

  return result
}

async function main() {
  const { data: convoRows } = await supabase
    .from("conversations")
    .select("id")
    .limit(1)
  const convo = convoRows?.[0]

  const { data: profilePosts } = await supabase
    .from("profile_posts")
    .select("id, user_id")
    .limit(1)
  const profilePost = profilePosts?.[0]

  const { data: tradePosts } = await supabase
    .from("posts")
    .select("id, user_id, trade_id")
    .limit(1)
  const tradePost = tradePosts?.[0]

  const senderId =
    profilePost?.user_id ?? tradePost?.user_id ?? null

  console.log("=== Context ===")
  console.log(
    JSON.stringify(
      {
        conversationId: convo?.id ?? null,
        senderId,
        profilePostId: profilePost?.id ?? null,
        tradePostId: tradePost?.id ?? null,
      },
      null,
      2
    )
  )

  if (!convo?.id || !senderId) {
    console.log("Missing conversation or sender for probe")
    return
  }

  const base = {
    conversation_id: convo.id,
    sender_id: senderId,
    ...POST_PAYLOAD_SHAPE,
  }

  const probes = []

  if (tradePost?.id) {
    probes.push(
      probeInsert("trade feed post (posts.id)", {
        ...base,
        post_id: tradePost.id,
      })
    )
  }

  if (profilePost?.id) {
    probes.push(
      probeInsert("profile wall post (profile_posts.id in post_id)", {
        ...base,
        post_id: profilePost.id,
      })
    )
    probes.push(
      probeInsert("profile_post_id column if exists", {
        ...base,
        post_id: null,
        profile_post_id: profilePost.id,
      })
    )
  }

  probes.push(
    probeInsert("fake post_id uuid", {
      ...base,
      post_id: "00000000-0000-4000-8000-000000000001",
    })
  )

  const results = await Promise.all(probes)
  console.log("\n=== Insert probes ===\n")
  console.log(JSON.stringify(results, null, 2))

  const { data: cols, error: colErr } = await supabase
    .from("messages")
    .select("*")
    .limit(1)

  console.log("\n=== messages columns (sample row keys) ===")
  if (colErr) console.log(colErr)
  else console.log(cols?.[0] ? Object.keys(cols[0]) : "(no rows)")
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
