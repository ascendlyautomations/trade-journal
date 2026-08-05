import { supabase } from "./supabaseClient"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard"
import {
  dispatchUnreadMessagesRefresh,
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

      // Cursor RPC unavailable: fail closed. Never SELECT/update unbounded
      // conversation history via seen_by (Phase 2 Disk IO safety).
      console.error(
        "[conversationReadMarking] mark_conversation_read unavailable; skipping mark-read"
      )
      return
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
