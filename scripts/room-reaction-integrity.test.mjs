/**
 * Staging integration: room_message_reactions message/room integrity.
 *
 * Requires env:
 *   NEXT_PUBLIC_SUPABASE_URL
 *   NEXT_PUBLIC_SUPABASE_ANON_KEY
 *   ROOM_INTEGRITY_TEST_EMAIL
 *   ROOM_INTEGRITY_TEST_PASSWORD
 *   ROOM_INTEGRITY_TEST_ROOM_A_ID
 *   ROOM_INTEGRITY_TEST_ROOM_B_ID
 *   ROOM_INTEGRITY_TEST_MESSAGE_A_ID  (message in room A)
 *
 * Run after applying 20260822220000_enforce_reaction_message_room_integrity.sql
 */
import { createClient } from "@supabase/supabase-js"

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const email = process.env.ROOM_INTEGRITY_TEST_EMAIL
const password = process.env.ROOM_INTEGRITY_TEST_PASSWORD
const roomA = process.env.ROOM_INTEGRITY_TEST_ROOM_A_ID
const roomB = process.env.ROOM_INTEGRITY_TEST_ROOM_B_ID
const messageA = process.env.ROOM_INTEGRITY_TEST_MESSAGE_A_ID

function required(name: string, value: string | undefined): string {
  if (!value?.trim()) {
    console.log(`SKIP room-reaction-integrity: missing ${name}`)
    process.exit(0)
  }
  return value.trim()
}

async function main() {
  const supabase = createClient(
    required("NEXT_PUBLIC_SUPABASE_URL", url),
    required("NEXT_PUBLIC_SUPABASE_ANON_KEY", anon)
  )

  const { error: signInErr } = await supabase.auth.signInWithPassword({
    email: required("ROOM_INTEGRITY_TEST_EMAIL", email),
    password: required("ROOM_INTEGRITY_TEST_PASSWORD", password),
  })
  if (signInErr) throw signInErr

  const roomAId = required("ROOM_INTEGRITY_TEST_ROOM_A_ID", roomA)
  const roomBId = required("ROOM_INTEGRITY_TEST_ROOM_B_ID", roomB)
  const messageAId = required("ROOM_INTEGRITY_TEST_MESSAGE_A_ID", messageA)

  // Legitimate insert omitting room_id
  const legit = await supabase
    .from("room_message_reactions")
    .insert({
      message_id: messageAId,
      user_id: (await supabase.auth.getUser()).data.user?.id,
      reaction: "👍",
    })
    .select("id, room_id")
    .maybeSingle()
  if (legit.error) throw new Error(`legit insert failed: ${legit.error.message}`)
  if (legit.data?.room_id !== roomAId) {
    throw new Error(`legit insert room_id mismatch: ${legit.data?.room_id}`)
  }
  await supabase.from("room_message_reactions").delete().eq("id", legit.data!.id)

  // Mismatched room_id must fail
  const mismatch = await supabase.from("room_message_reactions").insert({
    message_id: messageAId,
    room_id: roomBId,
    user_id: (await supabase.auth.getUser()).data.user?.id,
    reaction: "👍",
  })
  if (!mismatch.error) {
    throw new Error("expected mismatched room_id insert to fail")
  }

  console.log("room-reaction-integrity: OK")
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
