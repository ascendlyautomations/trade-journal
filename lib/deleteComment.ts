import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

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
    senderId: string
    content: string
    postId?: string | null
    tradeId?: string | null
  }
) {
  const snippet = params.content.trim().slice(0, 200)
  let query = supabase
    .from("notifications")
    .delete()
    .eq("type", "comment")
    .eq("sender_id", params.senderId)

  if (params.postId) {
    query = query.eq("post_id", params.postId)
  } else if (params.tradeId) {
    query = query.eq("trade_id", params.tradeId)
  } else {
    return
  }

  if (snippet) {
    query = query.eq("content", snippet)
  }

  const { error } = await query
  if (error) {
    logDeleteError("notification cleanup failed (comment already deleted)", {
      error,
      postId: params.postId,
      tradeId: params.tradeId,
    })
  }
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
    senderId: userId,
    content: String(comment.content ?? ""),
    tradeId: comment.trade_id != null ? String(comment.trade_id) : null,
  })

  return { error: null, deleted: true as const }
}
