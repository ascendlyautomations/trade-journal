import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"

const env = Object.fromEntries(
  readFileSync(".env.local", "utf8")
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=")
      return [l.slice(0, i), l.slice(i + 1)]
    })
)

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY)
const anon = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY)

const email = "tradetraxs@gmail.com"
const { data: link } = await admin.auth.admin.generateLink({ type: "magiclink", email })
const { data: sd } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
const userId = sd.session.user.id
const cid = "3eb7441b-4155-4a4d-8ee2-46ba5b3986f6"

const DM = `
  id, conversation_id, sender_id, sender_anonymized, content, created_at, seen_by,
  type, trade_id, post_id, profile_post_id, achievement_post_id, reel_id,
  parent_message_id, deleted_for_everyone, image_url, is_system,
  profiles!sender_id ( username, avatar_url )
`

const res = await anon
  .from("messages")
  .select(DM)
  .eq("conversation_id", cid)
  .order("created_at", { ascending: true })

console.log({
  error: res.error?.message ?? null,
  code: res.error?.code ?? null,
  count: res.data?.length ?? 0,
  first: res.data?.[0] ?? null,
})

const { data: my } = await anon
  .from("conversation_participants")
  .select("conversation_id")
  .eq("user_id", userId)
const ids = [...new Set((my || []).map((r) => r.conversation_id))]
const { data: allParts } = await anon
  .from("conversation_participants")
  .select("conversation_id, user_id")
  .in("conversation_id", ids)
const { data: metas } = await anon
  .from("conversations")
  .select("id, is_group, last_message, last_message_at")
  .in("id", ids)

const byConvo = new Map()
for (const r of allParts || []) {
  if (!byConvo.has(r.conversation_id)) byConvo.set(r.conversation_id, new Set())
  byConvo.get(r.conversation_id).add(r.user_id)
}

for (const m of (metas || []).filter((x) => !x.is_group)) {
  const users = [...(byConvo.get(m.id) || [])]
  const { count } = await anon
    .from("messages")
    .select("id", { count: "exact", head: true })
    .eq("conversation_id", m.id)
  console.log({ id: m.id, users, last: m.last_message, msgCount: count })
}
