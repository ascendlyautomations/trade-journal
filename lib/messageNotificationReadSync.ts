import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient.ts"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard.ts"
import { devLog } from "./devLog.ts"

const RECENT_MARK_MS = 8_000
const recentMarks = new Map<string, number>()
const inFlight = new Map<string, Promise<number>>()

/**
 * Mark unread message-type Activity notifications read when entering Messages scope.
 * Deduped per user — inbox + thread must not PATCH simultaneously.
 */
export async function markMessageNotificationsRead(
  userId: string,
  reason: "page-open" | "chat-open" | "thread-open" = "page-open",
  client: SupabaseClient = supabase
): Promise<number> {
  if (!userId || isDemoSupabaseBlocked()) return 0

  const key = userId
  const last = recentMarks.get(key)
  if (last != null && Date.now() - last < RECENT_MARK_MS) {
    const pending = inFlight.get(key)
    if (pending) return pending
    return 0
  }

  const pending = (async () => {
    devLog("[messages] mark read start", {
      reason,
      userId,
      type: "message",
    })

    const { data, error } = await client
      .from("notifications")
      .update({ read: true })
      .eq("user_id", userId)
      .eq("type", "message")
      .eq("read", false)
      .select("id,type")

    if (error) {
      console.error("[messages] mark read error:", {
        reason,
        userId,
        error,
      })
      return 0
    }

    const updated = data?.length ?? 0
    devLog("[messages] mark read success", {
      reason,
      userId,
      updated,
    })

    if (updated > 0 && typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }

    recentMarks.set(key, Date.now())
    return updated
  })()

  inFlight.set(key, pending)
  try {
    return await pending
  } finally {
    inFlight.delete(key)
  }
}

/** @internal */
export function resetMessageNotificationReadSyncForTests(): void {
  recentMarks.clear()
  inFlight.clear()
}
