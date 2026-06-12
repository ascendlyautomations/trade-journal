import type { SupabaseClient } from "@supabase/supabase-js"

async function authFetch(
  supabase: SupabaseClient,
  url: string,
  init: RequestInit
): Promise<Response | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[notifications] skipped: no auth session")
    return null
  }

  return fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      ...(init.headers as Record<string, string> | undefined),
    },
  })
}

/** Remove follow notification when the follow relationship is deleted. */
export async function removeFollowNotification(
  supabase: SupabaseClient,
  followerId: string,
  followingId: string
): Promise<boolean> {
  if (!followerId || !followingId || followerId === followingId) return false

  const res = await authFetch(supabase, "/api/notifications/follow", {
    method: "DELETE",
    body: JSON.stringify({ followingId }),
  })

  if (!res) return false

  if (!res.ok) {
    const body = await res.text()
    console.error("[follow] notification remove failed", {
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

/** Remove follow-request notification when the pending request is cancelled. */
export async function removeFollowRequestNotification(
  supabase: SupabaseClient,
  requesterId: string,
  targetId: string
): Promise<boolean> {
  if (!requesterId || !targetId || requesterId === targetId) return false

  const res = await authFetch(supabase, "/api/notifications/follow-request", {
    method: "DELETE",
    body: JSON.stringify({ targetId }),
  })

  if (!res) return false

  if (!res.ok) {
    const body = await res.text()
    console.error("[follow-request] notification remove failed", {
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

/** Delete all engagement notifications for the signed-in user. */
export async function clearAllNotifications(
  supabase: SupabaseClient
): Promise<boolean> {
  const res = await authFetch(supabase, "/api/notifications/clear", {
    method: "DELETE",
  })

  if (!res) return false

  if (!res.ok) {
    const body = await res.text()
    console.error("[notifications] clear all failed", {
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}

/** Delete one or more notifications belonging to the signed-in user. */
export async function dismissNotifications(
  supabase: SupabaseClient,
  ids: string[]
): Promise<boolean> {
  const uniqueIds = Array.from(new Set(ids.map((id) => String(id).trim()).filter(Boolean)))
  if (uniqueIds.length === 0) return false

  const res = await authFetch(supabase, "/api/notifications/dismiss", {
    method: "DELETE",
    body: JSON.stringify({ ids: uniqueIds }),
  })

  if (!res) return false

  if (!res.ok) {
    const body = await res.text()
    console.error("[notifications] dismiss failed", {
      ids: uniqueIds,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return true
}
