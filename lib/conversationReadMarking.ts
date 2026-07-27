import { supabase } from "./supabaseClient"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard"
import {
  dispatchUnreadMessagesRefresh,
  normalizeSeenBy,
} from "./messageUnread"

const RECENT_MARK_MS = 8_000
const recentMarks = new Map<string, number>()
const inFlight = new Map<string, Promise<void>>()

function isMissingReadCursorRpc(error: {
  code?: string
  message?: string
}): boolean {
  const message = String(error.message ?? "").toLowerCase()
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    message.includes("could not find the function") ||
    message.includes("schema cache")
  )
}

function markKey(userId: string, conversationId: string): string {
  return `${userId}:${conversationId}`
}

/** Mark inbound conversation messages as seen by the viewer (deduped per conversation). */
export async function markConversationMessagesSeen(
  userId: string,
  conversationId: string
): Promise<void> {
  if (!userId || !conversationId) return
  if (isDemoSupabaseBlocked()) return

  const key = markKey(userId, conversationId)
  const last = recentMarks.get(key)
  if (last != null && Date.now() - last < RECENT_MARK_MS) {
    const pendingRecent = inFlight.get(key)
    if (pendingRecent) return pendingRecent
    // Cursor already advanced; still refresh Navbar in case it missed the prior event.
    dispatchUnreadMessagesRefresh()
    return
  }

  const pending = (async () => {
    const { error: cursorError } = await supabase.rpc("mark_conversation_read", {
      p_conversation_id: conversationId,
    })

    if (cursorError) {
      if (!isMissingReadCursorRpc(cursorError)) {
        console.error("[conversationReadMarking] cursor error:", cursorError)
        return
      }

      // Deployment-safe fallback only while the read-cursor migration rolls out.
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
    }

    recentMarks.set(key, Date.now())
    // Navbar listens for this event (same path as mark-unread / mute / block).
    dispatchUnreadMessagesRefresh()
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
