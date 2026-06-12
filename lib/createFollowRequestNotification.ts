import type { SupabaseClient } from "@supabase/supabase-js"

/** Notify a private-profile owner of a pending follow request. */
export async function createFollowRequestNotification(
  supabase: SupabaseClient,
  requesterId: string,
  targetId: string
): Promise<boolean> {
  if (!requesterId || !targetId || requesterId === targetId) return false

  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[follow-request] notification skipped: no auth session")
    return false
  }

  const res = await fetch("/api/notifications/follow-request", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ targetId }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error("[follow-request] notification API failed", {
      requesterId,
      targetId,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}
