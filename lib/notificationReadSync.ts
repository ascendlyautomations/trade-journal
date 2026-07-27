import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"

export type NotificationReadTarget =
  | { kind: "conversation"; conversationId: string }
  | { kind: "room"; roomId: string; roomSlug?: string | null }
  | {
      kind: "feed"
      postId?: string | null
      tradeId?: string | null
      profilePostId?: string | null
      achievementPostId?: string | null
      reelId?: string | null
    }
  | { kind: "follow_request"; senderId?: string | null }

/**
 * Mark Activity notifications as read for a viewed target.
 * Does not delete history — only flips read=true.
 */
export async function markNotificationsReadForTarget(
  userId: string,
  target: NotificationReadTarget,
  client: SupabaseClient = supabase
): Promise<number> {
  if (!userId || isDemoSupabaseBlocked()) return 0

  let query = client
    .from("notifications")
    .update({ read: true })
    .eq("user_id", userId)
    .eq("read", false)

  if (target.kind === "conversation") {
    // Legacy message Activity rows (if any) + keep messaging unread via conversation RPC separately.
    query = query
      .eq("type", "message")
      .ilike("content", `%${target.conversationId}%`)
  } else if (target.kind === "room") {
    query = query.in("type", ["room_message", "room_mention", "room_join"])
    if (target.roomId) {
      query = query.or(
        `room_id.eq.${target.roomId},content.ilike.%${target.roomId}%`
      )
    } else if (target.roomSlug) {
      query = query.ilike("content", `%${target.roomSlug}%`)
    }
  } else if (target.kind === "feed") {
    query = query.in("type", ["like", "comment", "like_milestone"])
    const filters: string[] = []
    if (target.postId) filters.push(`post_id.eq.${target.postId}`)
    if (target.tradeId) filters.push(`trade_id.eq.${target.tradeId}`)
    if (target.profilePostId)
      filters.push(`profile_post_id.eq.${target.profilePostId}`)
    if (target.achievementPostId)
      filters.push(`achievement_post_id.eq.${target.achievementPostId}`)
    if (target.reelId) filters.push(`reel_id.eq.${target.reelId}`)
    if (filters.length === 0) return 0
    query = query.or(filters.join(","))
  } else if (target.kind === "follow_request") {
    query = query.eq("type", "follow_request")
    if (target.senderId) query = query.eq("sender_id", target.senderId)
  }

  const { data, error } = await query.select("id")
  if (error) {
    console.error("[notificationReadSync] mark failed", error)
    return 0
  }

  const updated = data?.length ?? 0
  if (updated > 0 && typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }
  return updated
}

export function dispatchNotificationReadRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
}
