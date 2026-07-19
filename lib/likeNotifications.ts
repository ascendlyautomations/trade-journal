import type { SupabaseClient } from "@supabase/supabase-js"

export type LikeNotificationTarget =
  | { kind: "trade"; tradeId: string }
  | { kind: "post"; postId: string; tradeId?: string | null }
  | { kind: "profile_post"; profilePostId: string }
  | { kind: "achievement_post"; achievementPostId: string }
  | { kind: "reel"; reelId: string }
  | {
      kind: "comment"
      commentId: string
      commentSource?: string | null
      postId?: string | null
      tradeId?: string | null
      profilePostId?: string | null
      achievementPostId?: string | null
      reelId?: string | null
    }

type LikeNotificationParams = {
  recipientUserId: string
  senderUserId: string
  target: LikeNotificationTarget
}

const UNIQUE_VIOLATION = "23505"

async function authFetch(
  supabase: SupabaseClient,
  method: "POST" | "DELETE",
  target: LikeNotificationTarget
): Promise<Response | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  if (!session?.access_token) return null
  return fetch("/api/notifications/like", {
    method,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ target }),
  })
}

function dispatchNotificationRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent("notification-update"))
  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
}

export function buildLikeNotificationInsertPayload(
  params: LikeNotificationParams
): Record<string, unknown> {
  const base = {
    user_id: params.recipientUserId,
    sender_id: params.senderUserId,
    type: "like",
  }

  if (params.target.kind === "trade") {
    return { ...base, trade_id: params.target.tradeId }
  }
  if (params.target.kind === "post") {
    return {
      ...base,
      post_id: params.target.postId,
      trade_id: params.target.tradeId ?? null,
    }
  }
  if (params.target.kind === "profile_post") {
    return { ...base, profile_post_id: params.target.profilePostId }
  }
  if (params.target.kind === "achievement_post") {
    return { ...base, achievement_post_id: params.target.achievementPostId }
  }
  if (params.target.kind === "comment") {
    return {
      ...base,
      comment_id: params.target.commentId,
      post_id: params.target.postId ?? null,
      trade_id: params.target.tradeId ?? null,
      profile_post_id: params.target.profilePostId ?? null,
      achievement_post_id: params.target.achievementPostId ?? null,
      reel_id: params.target.reelId ?? null,
    }
  }
  return { ...base, reel_id: params.target.reelId }
}

/** Create exactly one like notification for this actor + target. */
export async function ensureLikeNotification(
  supabase: SupabaseClient,
  params: LikeNotificationParams
): Promise<void> {
  const response = await authFetch(supabase, "POST", params.target)
  if (!response) return
  if (!response.ok) {
    const body = await response.text()
    if (response.status === 409 || body.includes(UNIQUE_VIOLATION)) {
      dispatchNotificationRefresh()
      return
    }
    console.error("Like notification insert error:", response.status, body)
    return
  }

  dispatchNotificationRefresh()
}

/** Remove all like notifications for this actor + target when the user unlikes. */
export async function deleteLikeNotification(
  supabase: SupabaseClient,
  params: LikeNotificationParams
): Promise<void> {
  const response = await authFetch(supabase, "DELETE", params.target)
  if (!response) return
  if (!response.ok) {
    console.error(
      "Like notification delete error:",
      response.status,
      await response.text()
    )
    return
  }

  dispatchNotificationRefresh()
}
