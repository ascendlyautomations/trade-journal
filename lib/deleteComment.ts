import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"
import {
  deleteCommentNotificationByCommentId,
  deleteLegacyCommentNotification,
} from "./commentNotifications"

export type FeedCommentRow = {
  id: string
  user_id: string
  content?: string | null
  post_id?: string | null
  parent_comment_id?: string | null
}

export type TradeCommentRow = {
  id: string
  user_id: string
  content?: string | null
  trade_id?: string | null
  parent_comment_id?: string | null
}

export type ProfilePostCommentRow = {
  id: string
  user_id: string
  content?: string | null
  profile_post_id?: string | null
  parent_comment_id?: string | null
}

export type AchievementPostCommentRow = {
  id: string
  user_id: string
  content?: string | null
  achievement_post_id?: string | null
  parent_comment_id?: string | null
}

const LOG_PREFIX = "[comment-delete]"

function logDeleteStep(step: string, details?: Record<string, unknown>) {
  if (details) {
    console.log(LOG_PREFIX, step, details)
  } else {
    console.log(LOG_PREFIX, step)
  }
}

function logDeleteError(step: string, details: Record<string, unknown>) {
  console.error(LOG_PREFIX, step, details)
}

function noRowDeletedError(table: "comments" | "trade_comments"): PostgrestError {
  return {
    name: "CommentDeleteError",
    message:
      table === "comments"
        ? "Comment was not deleted. Ensure the comments DELETE policy and grant are applied in Supabase."
        : "Trade comment was not deleted. Ensure the trade_comments DELETE policy and grant are applied in Supabase.",
    code: "PGRST116",
    details: "No rows deleted — likely missing RLS DELETE policy or DELETE grant.",
    hint: "Apply migration 20260623150000_comment_delete_policies.sql",
  } as PostgrestError
}

/** Remove a deleted comment and any direct reply children from local state. */
export function filterCommentsAfterDelete<
  T extends { id: string | number; parent_comment_id?: string | null },
>(comments: T[], deletedCommentId: string): T[] {
  const removeIds = new Set<string>([String(deletedCommentId)])
  let changed = true
  while (changed) {
    changed = false
    for (const comment of comments) {
      const id = String(comment.id)
      if (removeIds.has(id)) continue
      const parentId =
        comment.parent_comment_id != null
          ? String(comment.parent_comment_id)
          : null
      if (parentId && removeIds.has(parentId)) {
        removeIds.add(id)
        changed = true
      }
    }
  }
  return comments.filter((comment) => !removeIds.has(String(comment.id)))
}

async function cleanupCommentNotifications(
  supabase: SupabaseClient,
  params: {
    commentId: string
    senderId: string
    content: string
    postId?: string | null
    tradeId?: string | null
    profilePostId?: string | null
    achievementPostId?: string | null
  }
) {
  await deleteCommentNotificationByCommentId(
    supabase,
    params.commentId,
    params.senderId
  )

  await deleteLegacyCommentNotification(supabase, {
    senderId: params.senderId,
    content: params.content,
    postId: params.postId,
    tradeId: params.tradeId,
    profilePostId: params.profilePostId,
    achievementPostId: params.achievementPostId,
  })
}

function noProfilePostRowDeletedError(): PostgrestError {
  return {
    name: "CommentDeleteError",
    message:
      "Profile post comment was not deleted. Ensure the profile_post_comments DELETE policy and grant are applied in Supabase.",
    code: "PGRST116",
    details: "No rows deleted — likely missing RLS DELETE policy or DELETE grant.",
    hint: "Apply migration 20260624000000_profile_post_engagement.sql",
  } as PostgrestError
}

export async function deleteProfilePostComment(
  supabase: SupabaseClient,
  comment: ProfilePostCommentRow
) {
  const commentId = String(comment.id)
  const userId = String(comment.user_id)

  logDeleteStep("supabase delete starting", {
    table: "profile_post_comments",
    commentId,
    userId,
    profilePostId: comment.profile_post_id ?? null,
  })

  const { data, error } = await supabase
    .from("profile_post_comments")
    .delete()
    .eq("id", commentId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle()

  logDeleteStep("supabase delete result", {
    table: "profile_post_comments",
    commentId,
    userId,
    deletedId: data?.id ?? null,
    error: error ?? null,
  })

  if (error) {
    logDeleteError("supabase delete failed", {
      table: "profile_post_comments",
      commentId,
      userId,
      error,
    })
    return { error, deleted: false as const }
  }

  if (!data) {
    const blocked = noProfilePostRowDeletedError()
    logDeleteError("supabase delete returned no row", {
      table: "profile_post_comments",
      commentId,
      userId,
      hint: blocked.hint,
    })
    return { error: blocked, deleted: false as const }
  }

  await cleanupCommentNotifications(supabase, {
    commentId,
    senderId: userId,
    content: String(comment.content ?? ""),
    profilePostId:
      comment.profile_post_id != null ? String(comment.profile_post_id) : null,
  })

  return { error: null, deleted: true as const }
}

function noAchievementPostRowDeletedError(): PostgrestError {
  return {
    name: "CommentDeleteError",
    message:
      "Achievement post comment was not deleted. Ensure the achievement_post_comments DELETE policy and grant are applied in Supabase.",
    code: "PGRST116",
    details: "No rows deleted — likely missing RLS DELETE policy or DELETE grant.",
    hint: "Apply migration 20260626150000_achievement_posts_social.sql",
  } as PostgrestError
}

export async function deleteAchievementPostComment(
  supabase: SupabaseClient,
  comment: AchievementPostCommentRow
) {
  const commentId = String(comment.id)
  const userId = String(comment.user_id)

  logDeleteStep("supabase delete starting", {
    table: "achievement_post_comments",
    commentId,
    userId,
    achievementPostId: comment.achievement_post_id ?? null,
  })

  const { data, error } = await supabase
    .from("achievement_post_comments")
    .delete()
    .eq("id", commentId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle()

  logDeleteStep("supabase delete result", {
    table: "achievement_post_comments",
    commentId,
    userId,
    deletedId: data?.id ?? null,
    error: error ?? null,
  })

  if (error) {
    logDeleteError("supabase delete failed", {
      table: "achievement_post_comments",
      commentId,
      userId,
      error,
    })
    return { error, deleted: false as const }
  }

  if (!data) {
    const blocked = noAchievementPostRowDeletedError()
    logDeleteError("supabase delete returned no row", {
      table: "achievement_post_comments",
      commentId,
      userId,
      hint: blocked.hint,
    })
    return { error: blocked, deleted: false as const }
  }

  await cleanupCommentNotifications(supabase, {
    commentId,
    senderId: userId,
    content: String(comment.content ?? ""),
    achievementPostId:
      comment.achievement_post_id != null
        ? String(comment.achievement_post_id)
        : null,
  })

  return { error: null, deleted: true as const }
}

export async function deleteFeedComment(
  supabase: SupabaseClient,
  comment: FeedCommentRow
) {
  const commentId = String(comment.id)
  const userId = String(comment.user_id)

  logDeleteStep("supabase delete starting", {
    table: "comments",
    commentId,
    userId,
    postId: comment.post_id ?? null,
  })

  const { data, error } = await supabase
    .from("comments")
    .delete()
    .eq("id", commentId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle()

  logDeleteStep("supabase delete result", {
    table: "comments",
    commentId,
    userId,
    deletedId: data?.id ?? null,
    error: error ?? null,
  })

  if (error) {
    logDeleteError("supabase delete failed", {
      table: "comments",
      commentId,
      userId,
      error,
    })
    return { error, deleted: false as const }
  }

  if (!data) {
    const blocked = noRowDeletedError("comments")
    logDeleteError("supabase delete returned no row", {
      table: "comments",
      commentId,
      userId,
      hint: blocked.hint,
    })
    return { error: blocked, deleted: false as const }
  }

  await cleanupCommentNotifications(supabase, {
    commentId,
    senderId: userId,
    content: String(comment.content ?? ""),
    postId: comment.post_id != null ? String(comment.post_id) : null,
  })

  return { error: null, deleted: true as const }
}

export async function deleteTradeComment(
  supabase: SupabaseClient,
  comment: TradeCommentRow
) {
  const commentId = String(comment.id)
  const userId = String(comment.user_id)

  logDeleteStep("supabase delete starting", {
    table: "trade_comments",
    commentId,
    userId,
    tradeId: comment.trade_id ?? null,
  })

  const { data, error } = await supabase
    .from("trade_comments")
    .delete()
    .eq("id", commentId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle()

  logDeleteStep("supabase delete result", {
    table: "trade_comments",
    commentId,
    userId,
    deletedId: data?.id ?? null,
    error: error ?? null,
  })

  if (error) {
    logDeleteError("supabase delete failed", {
      table: "trade_comments",
      commentId,
      userId,
      error,
    })
    return { error, deleted: false as const }
  }

  if (!data) {
    const blocked = noRowDeletedError("trade_comments")
    logDeleteError("supabase delete returned no row", {
      table: "trade_comments",
      commentId,
      userId,
      hint: blocked.hint,
    })
    return { error: blocked, deleted: false as const }
  }

  await cleanupCommentNotifications(supabase, {
    commentId,
    senderId: userId,
    content: String(comment.content ?? ""),
    tradeId: comment.trade_id != null ? String(comment.trade_id) : null,
  })

  return { error: null, deleted: true as const }
}
