/**
 * Staging: verify room_messages INSERT return embed after PGRST201 fix.
 *
 * Requires:
 *   NEXT_PUBLIC_SUPABASE_URL
 *   NEXT_PUBLIC_SUPABASE_ANON_KEY
 *   ROOM_SEND_TEST_EMAIL / ROOM_SEND_TEST_PASSWORD
 *   ROOM_SEND_TEST_ROOM_ID
 *   ROOM_SEND_TEST_SECTION_ID (optional)
 */
import { createClient } from "@supabase/supabase-js"
import { ROOM_MESSAGE_SELECT_COMPACT } from "../lib/roomMessageSelect.ts"

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const email = process.env.ROOM_SEND_TEST_EMAIL
const password = process.env.ROOM_SEND_TEST_PASSWORD
const roomId = process.env.ROOM_SEND_TEST_ROOM_ID
const sectionId = process.env.ROOM_SEND_TEST_SECTION_ID

function req(name: string, v: string | undefined): string {
  if (!v?.trim()) {
    console.log(`SKIP room-message-send: missing ${name}`)
    process.exit(0)
  }
  return v.trim()
}

async function main() {
  const supabase = createClient(req("URL", url), req("ANON", anon))
  const { error: signErr } = await supabase.auth.signInWithPassword({
    email: req("ROOM_SEND_TEST_EMAIL", email),
    password: req("ROOM_SEND_TEST_PASSWORD", password),
  })
  if (signErr) throw signErr

  const uid = (await supabase.auth.getUser()).data.user?.id
  if (!uid) throw new Error("no user")

  const tag = `pgrst201-fix-${Date.now()}`
  const { data, error } = await supabase
    .from("room_messages")
    .insert({
      room_id: req("ROOM_SEND_TEST_ROOM_ID", roomId),
      user_id: uid,
      content: tag,
      section_id: sectionId?.trim() || null,
    })
    .select(ROOM_MESSAGE_SELECT_COMPACT)
    .single()

  if (error) {
    throw new Error(`insert failed: ${error.code} ${error.message}`)
  }

  if (!Array.isArray(data?.room_message_reactions)) {
    throw new Error("expected room_message_reactions array in response")
  }

  await supabase.from("room_messages").delete().eq("id", data.id)
  console.log("room-message-send: OK", { id: data.id, tag })
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
