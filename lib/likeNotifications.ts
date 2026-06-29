import type { SupabaseClient } from "@supabase/supabase-js"

export type LikeNotificationTarget =
  | { kind: "trade"; tradeId: string }
  | { kind: "post"; postId: string; tradeId?: string | null }
  | { kind: "profile_post"; profilePostId: string }
  | { kind: "achievement_post"; achievementPostId: string }
  | { kind: "reel"; reelId: string }

type LikeNotificationParams = {
  recipientUserId: string
  senderUserId: string
  target: LikeNotificationTarget
}

const UNIQUE_VIOLATION = "23505"

function dispatchNotificationRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent("notification-update"))
  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
}

function applyTargetFilter<
  Q extends {
    eq: (column: string, value: string) => Q
  },
>(query: Q, target: LikeNotificationTarget): Q {
  if (target.kind === "trade") {
    return query.eq("trade_id", target.tradeId)
  }
  if (target.kind === "post") {
    return query.eq("post_id", target.postId)
  }
  if (target.kind === "profile_post") {
    return query.eq("profile_post_id", target.profilePostId)
  }
  if (target.kind === "achievement_post") {
    return query.eq("achievement_post_id", target.achievementPostId)
  }
  return query.eq("reel_id", target.reelId)
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
  return { ...base, reel_id: params.target.reelId }
}

/** Create exactly one like notification for this actor + target. */
export async function ensureLikeNotification(
  supabase: SupabaseClient,
  params: LikeNotificationParams
): Promise<void> {
  if (params.recipientUserId === params.senderUserId) return

  const { error } = await supabase
    .from("notifications")
    .insert(buildLikeNotificationInsertPayload(params))

  if (error) {
    if (error.code === UNIQUE_VIOLATION) {
      dispatchNotificationRefresh()
      return
    }
    console.error("Like notification insert error:", error.message, error)
    return
  }

  dispatchNotificationRefresh()
}

/** Remove all like notifications for this actor + target when the user unlikes. */
export async function deleteLikeNotification(
  supabase: SupabaseClient,
  params: LikeNotificationParams
): Promise<void> {
  if (params.recipientUserId === params.senderUserId) return

  let query = supabase
    .from("notifications")
    .delete()
    .eq("type", "like")
    .eq("user_id", params.recipientUserId)
    .eq("sender_id", params.senderUserId)

  query = applyTargetFilter(query, params.target)

  const { error } = await query

  if (error) {
    console.error("Like notification delete error:", error.message, error)
    return
  }

  dispatchNotificationRefresh()
}
