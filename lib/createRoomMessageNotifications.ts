import type { SupabaseClient } from "@supabase/supabase-js"

/** Notify active room members (notification_enabled) after a message is posted. */
export async function createRoomMessageNotifications(
  _supabase: SupabaseClient,
  messageId: string
): Promise<boolean> {
  if (!messageId) return false

  const {
    data: { session },
  } = await _supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[room_message] notification skipped: no auth session")
    return false
  }

  const res = await fetch("/api/notifications/room-message", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ messageId }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error("[room_message] notification API failed", {
      messageId,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}
