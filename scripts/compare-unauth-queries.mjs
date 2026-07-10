/**
 * Compare unauthenticated + nested-null behavior for inbox vs share loaders.
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

const anon = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

const fakeUserId = "00000000-0000-4000-8000-000000000001"

console.log("=== UNAUTHENTICATED: inbox nested embed ===")
const inbox = await anon
  .from("conversation_participants")
  .select(
    `conversation_id, conversations (id, is_group, is_pinned, name, avatar_url, last_message, last_message_at)`
  )
  .eq("user_id", fakeUserId)
console.log({ rowCount: inbox.data?.length ?? 0, error: inbox.error?.message ?? null })

console.log("\n=== UNAUTHENTICATED: share step 1 ===")
const s1 = await anon
  .from("conversation_participants")
  .select("conversation_id")
  .eq("user_id", fakeUserId)
console.log({ rowCount: s1.data?.length ?? 0, error: s1.error?.message ?? null })

console.log("\n=== UNAUTHENTICATED: room_messages ===")
const room = await anon
  .from("room_messages")
  .select("id, room_id, content")
  .eq("room_id", "ab007232-067b-49d3-b5de-ff52857b8c14")
  .limit(5)
console.log({ rowCount: room.data?.length ?? 0, error: room.error?.message ?? null })
