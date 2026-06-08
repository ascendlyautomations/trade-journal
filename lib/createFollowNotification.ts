import type { SupabaseClient } from "@supabase/supabase-js"

/** Notify a user when someone follows them. Call only after a successful follow insert. */
export async function createFollowNotification(
  supabase: SupabaseClient,
  followerId: string,
  followingId: string
): Promise<boolean> {
  if (!followerId || !followingId || followerId === followingId) return false

  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[follow] notification skipped: no auth session")
    return false
  }

  const res = await fetch("/api/notifications/follow", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ followingId }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error("[follow] notification API failed", {
      followerId,
      followingId,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}
