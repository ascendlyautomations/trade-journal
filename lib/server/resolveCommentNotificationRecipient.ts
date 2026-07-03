import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export type CommentNotificationTargetInput = {
  postId?: string | null
  tradeId?: string | null
  profilePostId?: string | null
  achievementPostId?: string | null
  reelId?: string | null
}

/** Derive the content owner server-side — never trust client recipientUserId. */
export async function resolveCommentNotificationRecipient(
  target: CommentNotificationTargetInput
): Promise<string | null> {
  if (target.profilePostId) {
    const { data } = await supabaseServiceRole
      .from("profile_posts")
      .select("user_id")
      .eq("id", target.profilePostId)
      .maybeSingle()
    return data?.user_id ? String(data.user_id) : null
  }

  if (target.achievementPostId) {
    const { data } = await supabaseServiceRole
      .from("achievement_posts")
      .select("user_id")
      .eq("id", target.achievementPostId)
      .maybeSingle()
    return data?.user_id ? String(data.user_id) : null
  }

  if (target.reelId) {
    const { data } = await supabaseServiceRole
      .from("reels")
      .select("user_id")
      .eq("id", target.reelId)
      .maybeSingle()
    return data?.user_id ? String(data.user_id) : null
  }

  if (target.postId) {
    const { data } = await supabaseServiceRole
      .from("posts")
      .select("user_id")
      .eq("id", target.postId)
      .maybeSingle()
    return data?.user_id ? String(data.user_id) : null
  }

  if (target.tradeId) {
    const { data } = await supabaseServiceRole
      .from("trades")
      .select("user_id")
      .eq("id", target.tradeId)
      .maybeSingle()
    return data?.user_id ? String(data.user_id) : null
  }

  return null
}
