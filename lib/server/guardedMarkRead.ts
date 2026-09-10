import type { SupabaseClient } from "@supabase/supabase-js"
import { normalizeSeenBy } from "@/lib/messageUnread"

const CURSOR_SENTINEL_ID = "ffffffff-ffff-ffff-ffff-ffffffffffff"

function cursorIsBehind(
  lastReadAt: string | null | undefined,
  lastReadMessageId: string | null | undefined,
  latestCreatedAt: string,
  latestMessageId: string
): boolean {
  if (!lastReadAt) return true
  const readMs = new Date(lastReadAt).getTime()
  const latestMs = new Date(latestCreatedAt).getTime()
  if (readMs < latestMs) return true
  if (readMs > latestMs) return false
  const readId = lastReadMessageId ?? CURSOR_SENTINEL_ID
  return readId < latestMessageId
}

/**
 * Service-role mark-read aligned with `mark_conversation_read` RPC guards —
 * skips prefs/seen_by writes when cursor is already at or past latest message.
 */
export async function markConversationReadForUser(
  db: SupabaseClient,
  userId: string,
  conversationId: string
): Promise<void> {
  const { data: latest, error: latestError } = await db
    .from("messages")
    .select("id, created_at, sender_id")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (latestError) {
    console.error("[guardedMarkRead] conversation latest message:", latestError)
    return
  }

  if (!latest?.id || !latest.created_at) return

  const { data: prefs, error: prefsError } = await db
    .from("conversation_member_preferences")
    .select("last_read_at, last_read_message_id")
    .eq("user_id", userId)
    .eq("conversation_id", conversationId)
    .maybeSingle()

  if (prefsError) {
    console.error("[guardedMarkRead] conversation prefs read:", prefsError)
    return
  }

  const needsPrefsUpdate = cursorIsBehind(
    prefs?.last_read_at,
    prefs?.last_read_message_id,
    latest.created_at,
    latest.id
  )

  if (needsPrefsUpdate) {
    const { error: upsertError } = await db
      .from("conversation_member_preferences")
      .upsert(
        {
          user_id: userId,
          conversation_id: conversationId,
          last_read_at: latest.created_at,
          last_read_message_id: latest.id,
        },
        { onConflict: "user_id,conversation_id" }
      )
    if (upsertError) {
      console.error("[guardedMarkRead] conversation prefs upsert:", upsertError)
      return
    }
  }

  if (latest.sender_id === userId) return

  const { data: messageRow, error: messageError } = await db
    .from("messages")
    .select("seen_by")
    .eq("id", latest.id)
    .maybeSingle()

  if (messageError || !messageRow) return

  const seen = normalizeSeenBy(messageRow.seen_by)
  if (seen.includes(userId)) return

  const { error: seenError } = await db
    .from("messages")
    .update({ seen_by: [...seen, userId] })
    .eq("id", latest.id)

  if (seenError) {
    console.error("[guardedMarkRead] conversation seen_by:", seenError)
  }
}

/**
 * Service-role mark-read aligned with `mark_room_read` RPC guards.
 */
export async function markRoomReadForUser(
  db: SupabaseClient,
  userId: string,
  roomId: string
): Promise<void> {
  const { data: latest, error: latestError } = await db
    .from("room_messages")
    .select("id, created_at, user_id")
    .eq("room_id", roomId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (latestError) {
    console.error("[guardedMarkRead] room latest message:", latestError)
    return
  }

  if (!latest?.id || !latest.created_at) return

  const { data: member, error: memberError } = await db
    .from("room_members")
    .select("last_read_at, last_read_message_id")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .is("left_at", null)
    .maybeSingle()

  if (memberError) {
    console.error("[guardedMarkRead] room member read:", memberError)
    return
  }

  const needsMemberUpdate = cursorIsBehind(
    member?.last_read_at,
    member?.last_read_message_id,
    latest.created_at,
    latest.id
  )

  if (needsMemberUpdate) {
    const { error: memberUpdateError } = await db
      .from("room_members")
      .update({
        last_read_at: latest.created_at,
        last_read_message_id: latest.id,
      })
      .eq("room_id", roomId)
      .eq("user_id", userId)
      .is("left_at", null)

    if (memberUpdateError) {
      console.error("[guardedMarkRead] room member update:", memberUpdateError)
      return
    }
  }

  if (latest.user_id === userId) return

  const { data: messageRow, error: messageError } = await db
    .from("room_messages")
    .select("seen_by")
    .eq("id", latest.id)
    .maybeSingle()

  if (messageError || !messageRow) return

  const rawSeen = messageRow.seen_by
  const seenArray: string[] = Array.isArray(rawSeen)
    ? rawSeen.map(String)
    : typeof rawSeen === "string"
      ? (() => {
          try {
            const parsed = JSON.parse(rawSeen)
            return Array.isArray(parsed) ? parsed.map(String) : []
          } catch {
            return []
          }
        })()
      : []

  if (seenArray.includes(userId)) return

  const { error: seenError } = await db
    .from("room_messages")
    .update({ seen_by: [...seenArray, userId] })
    .eq("id", latest.id)

  if (seenError) {
    console.error("[guardedMarkRead] room seen_by:", seenError)
  }
}
