import { supabase } from "./supabaseClient"
import { normalizeSeenBy } from "./messageUnread"

const RECENT_MARK_MS = 8_000
const recentMarks = new Map<string, number>()
const inFlight = new Map<string, Promise<void>>()

function markKey(userId: string, conversationId: string): string {
  return `${userId}:${conversationId}`
}

/** Mark inbound conversation messages as seen by the viewer (deduped per conversation). */
export async function markConversationMessagesSeen(
  userId: string,
  conversationId: string
): Promise<void> {
  if (!userId || !conversationId) return

  const key = markKey(userId, conversationId)
  const last = recentMarks.get(key)
  if (last != null && Date.now() - last < RECENT_MARK_MS) {
    return inFlight.get(key) ?? Promise.resolve()
  }

  const pending = (async () => {
    const { data: rows, error: fetchErr } = await supabase
      .from("messages")
      .select("id, sender_id, seen_by")
      .eq("conversation_id", conversationId)

    if (fetchErr) {
      console.error("[conversationReadMarking] fetch error:", fetchErr)
      return
    }

    const updates: Promise<unknown>[] = []
    for (const row of rows || []) {
      if (!row.sender_id || row.sender_id === userId) continue
      const seenBy = normalizeSeenBy(row.seen_by)
      if (seenBy.includes(userId)) continue
      updates.push(
        supabase
          .from("messages")
          .update({ seen_by: [...seenBy, userId] })
          .eq("id", row.id)
      )
    }

    if (updates.length > 0) {
      await Promise.all(updates)
    }

    recentMarks.set(key, Date.now())
  })()

  inFlight.set(key, pending)
  try {
    await pending
  } finally {
    inFlight.delete(key)
  }
}

export function resetConversationReadMarkingForTests() {
  recentMarks.clear()
  inFlight.clear()
}
