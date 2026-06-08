import type { SupabaseClient } from "@supabase/supabase-js"

/** Notify a room owner when someone joins. Call only after a successful join/rejoin. */
export async function createRoomJoinNotification(
  supabase: SupabaseClient,
  roomId: string
): Promise<boolean> {
  if (!roomId) return false

  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[room_join] notification skipped: no auth session")
    return false
  }

  const res = await fetch("/api/notifications/room-join", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ roomId }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error("[room_join] notification API failed", {
      roomId,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}
