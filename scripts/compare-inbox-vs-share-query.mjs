/**
 * Compare inbox nested-embed query vs shareToConversations two-step query.
 */
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

const admin = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)
const anon = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

const email = "tradetraxs@gmail.com"
const { data: link } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email,
})
const { data: sd } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
const userId = sd.session.user.id

console.log("=== INBOX QUERY (conversation_participants parent + conversations embed) ===")
const inbox = await anon
  .from("conversation_participants")
  .select(
    `
    conversation_id,
    conversations (
      id,
      is_group,
      is_pinned,
      name,
      avatar_url,
      last_message,
      last_message_at
    )
  `
  )
  .eq("user_id", userId)
console.log({
  error: inbox.error?.message ?? null,
  rowCount: inbox.data?.length ?? 0,
  firstRow: inbox.data?.[0] ?? null,
})

console.log("\n=== SHARE QUERY STEP 1 (conversation_id only) ===")
const step1 = await anon
  .from("conversation_participants")
  .select("conversation_id")
  .eq("user_id", userId)
const ids = [...new Set((step1.data ?? []).map((r) => r.conversation_id))]
console.log({
  error: step1.error?.message ?? null,
  rowCount: ids.length,
})

console.log("\n=== SHARE QUERY STEP 2 (conversations parent + participants alias embed) ===")
const step2 = await anon
  .from("conversations")
  .select(
    `
    id,
    is_group,
    name,
    avatar_url,
    last_message_at,
    participants:conversation_participants(
      user_id,
      profiles (
        id,
        username,
        avatar_url
      )
    )
  `
  )
  .in("id", ids)
console.log({
  error: step2.error?.message ?? null,
  rowCount: step2.data?.length ?? 0,
  firstRow: step2.data?.[0] ?? null,
})

console.log("\n=== ROOM MESSAGES QUERY (pinned sample) ===")
const { data: rooms } = await admin.from("room_members").select("room_id").eq("user_id", userId).limit(1)
const roomId = rooms?.[0]?.room_id
if (roomId) {
  const room = await anon
    .from("room_messages")
    .select(
      `
      *,
      trades!room_messages_trade_id_fkey ( id, ticker ),
      profiles ( username, avatar_url ),
      room_message_reactions ( id, user_id, reaction )
    `
    )
    .eq("room_id", roomId)
    .eq("pinned", false)
    .order("created_at", { ascending: false })
    .limit(5)
  console.log({
    roomId,
    error: room.error?.message ?? null,
    rowCount: room.data?.length ?? 0,
  })
} else {
  console.log("user not in any room")
}
