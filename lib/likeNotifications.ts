import type { SupabaseClient } from "@supabase/supabase-js"

export type LikeNotificationTarget =
  | { kind: "trade"; tradeId: string }
  | { kind: "post"; postId: string; tradeId?: string | null }
  | { kind: "profile_post"; profilePostId: string }

type LikeNotificationParams = {
  recipientUserId: string
  senderUserId: string
  target: LikeNotificationTarget
}

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
  return query.eq("profile_post_id", target.profilePostId)
}

function buildInsertPayload(params: LikeNotificationParams): Record<string, unknown> {
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
  return { ...base, profile_post_id: params.target.profilePostId }
}

/** Create a like notification, or skip if one already exists for this actor + target. */
export async function ensureLikeNotification(
  supabase: SupabaseClient,
  params: LikeNotificationParams
): Promise<void> {
  if (params.recipientUserId === params.senderUserId) return

  let findQuery = supabase
    .from("notifications")
    .select("id")
    .eq("type", "like")
    .eq("user_id", params.recipientUserId)
    .eq("sender_id", params.senderUserId)
    .limit(1)

  findQuery = applyTargetFilter(findQuery, params.target)

  const { data: existing, error: findError } = await findQuery.maybeSingle()

  if (findError) {
    console.error("Like notification lookup error:", findError.message, findError)
    return
  }

  if (existing?.id) {
    dispatchNotificationRefresh()
    return
  }

  const { error } = await supabase
    .from("notifications")
    .insert(buildInsertPayload(params))

  if (error) {
    console.error("Like notification insert error:", error.message, error)
    return
  }

  dispatchNotificationRefresh()
}

/** Remove like notification(s) when the user unlikes (cleans legacy duplicates too). */
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
