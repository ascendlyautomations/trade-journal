import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "./supabaseClient.ts"
import { NOTIFICATION_INBOX_TYPES } from "./notificationEngagementTypes.ts"

const inFlight = new Map<string, Promise<number>>()

/**
 * HEAD count for unread social Activity notifications (excludes message type).
 * Single in-flight per user for the mounted shell.
 */
export async function fetchSocialNotificationUnreadCount(
  userId: string,
  client: SupabaseClient = supabase
): Promise<number> {
  const uid = userId.trim()
  if (!uid) return 0

  const existing = inFlight.get(uid)
  if (existing) return existing

  const pending = (async () => {
    const { count, error } = await client
      .from("notifications")
      .select("*", { count: "exact", head: true })
      .eq("user_id", uid)
      .eq("read", false)
      .in("type", [...NOTIFICATION_INBOX_TYPES])

    if (error) {
      console.error("[notifications] unread social count failed", {
        userId: uid,
        message: error.message,
        code: error.code,
      })
      return 0
    }

    return count ?? 0
  })()

  inFlight.set(uid, pending)
  try {
    return await pending
  } finally {
    if (inFlight.get(uid) === pending) {
      inFlight.delete(uid)
    }
  }
}

/** @internal */
export function resetSocialNotificationUnreadCountForTests(): void {
  inFlight.clear()
}
