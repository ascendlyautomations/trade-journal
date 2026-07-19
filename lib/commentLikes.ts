import type { SupabaseClient } from "@supabase/supabase-js"
import { isAchievementFeedPost } from "@/lib/achievementPostEngagement"
import { isProfileFeedPost } from "@/lib/profilePostEngagement"
import { isReelFeedPost } from "@/lib/reelEngagement"
import {
  deleteLikeNotification,
  ensureLikeNotification,
} from "./likeNotifications"

export type CommentLikeSource =
  | "comments"
  | "trade_comments"
  | "profile_post_comments"
  | "achievement_post_comments"
  | "reel_comments"

export type CommentLikeMeta = { count: number; liked: boolean }

export type CommentLikeNotificationParent = {
  postId?: string | null
  tradeId?: string | null
  profilePostId?: string | null
  achievementPostId?: string | null
  reelId?: string | null
}

const UNIQUE_VIOLATION = "23505"

export function commentLikeSourceFromFeedPost(
  post: { feedKind?: string; video_url?: unknown } | null | undefined
): CommentLikeSource {
  if (isReelFeedPost(post)) return "reel_comments"
  if (isAchievementFeedPost(post)) return "achievement_post_comments"
  if (isProfileFeedPost(post)) return "profile_post_comments"
  return "comments"
}

export function commentLikeNotificationParentFromFeedPost(
  post: {
    id?: string | number | null
    feedKind?: string
    video_url?: unknown
    trade_id?: string | null
  } | null
  | undefined
): CommentLikeNotificationParent {
  if (!post?.id) return {}
  const contentId = String(post.id)
  if (isReelFeedPost(post)) return { reelId: contentId }
  if (isAchievementFeedPost(post)) return { achievementPostId: contentId }
  if (isProfileFeedPost(post)) return { profilePostId: contentId }
  return {
    postId: contentId,
    tradeId: post.trade_id != null ? String(post.trade_id) : null,
  }
}

export function commentLikeNotificationParentFromTradeId(
  tradeId: string | number
): CommentLikeNotificationParent {
  return { tradeId: String(tradeId) }
}

export function commentLikeLabel(meta: CommentLikeMeta): string {
  const heart = meta.liked ? "❤️" : "♡"
  if (meta.count > 0) return `${heart} ${meta.count}`
  return heart
}

export async function fetchCommentLikeMetaByIds(
  client: SupabaseClient,
  commentSource: CommentLikeSource,
  commentIds: string[],
  currentUserId: string | null | undefined
): Promise<Record<string, CommentLikeMeta>> {
  const meta: Record<string, CommentLikeMeta> = {}
  for (const id of commentIds) {
    meta[id] = { count: 0, liked: false }
  }
  if (commentIds.length === 0) return meta

  const { data, error } = await client
    .from("comment_likes")
    .select("comment_id, user_id")
    .eq("comment_source", commentSource)
    .in("comment_id", commentIds)

  if (error) {
    console.error("[comment-likes] fetch meta failed", error)
    return meta
  }

  for (const row of data ?? []) {
    const cid = String(row.comment_id)
    if (!meta[cid]) meta[cid] = { count: 0, liked: false }
    meta[cid].count++
    if (currentUserId && row.user_id === currentUserId) {
      meta[cid].liked = true
    }
  }

  return meta
}

function buildCommentLikeNotificationTarget(
  commentId: string,
  commentSource: CommentLikeSource,
  parent: CommentLikeNotificationParent
) {
  return {
    kind: "comment" as const,
    commentId,
    commentSource,
    postId: parent.postId ?? null,
    tradeId: parent.tradeId ?? null,
    profilePostId: parent.profilePostId ?? null,
    achievementPostId: parent.achievementPostId ?? null,
    reelId: parent.reelId ?? null,
  }
}

export async function toggleCommentLike(
  client: SupabaseClient,
  params: {
    commentSource: CommentLikeSource
    commentId: string
    userId: string
    authorUserId: string | null
    meta: CommentLikeMeta
    notificationParent: CommentLikeNotificationParent
    onMetaChange: (next: CommentLikeMeta) => void
  }
): Promise<boolean> {
  const commentId = params.commentId.trim()
  const {
    commentSource,
    userId,
    authorUserId,
    meta,
    notificationParent,
    onMetaChange,
  } = params
  if (!commentId || !userId) return false

  const optimistic: CommentLikeMeta = meta.liked
    ? { count: Math.max(0, meta.count - 1), liked: false }
    : { count: meta.count + 1, liked: true }

  onMetaChange(optimistic)

  try {
    if (meta.liked) {
      const { error } = await client
        .from("comment_likes")
        .delete()
        .eq("comment_source", commentSource)
        .eq("comment_id", commentId)
        .eq("user_id", userId)

      if (error) {
        console.error("[comment-like] unlike failed", error)
        onMetaChange(meta)
        return false
      }

      if (authorUserId) {
        await deleteLikeNotification(client, {
          recipientUserId: authorUserId,
          senderUserId: userId,
          target: buildCommentLikeNotificationTarget(
            commentId,
            commentSource,
            notificationParent
          ),
        })
      }

      return true
    }

    const { error } = await client.from("comment_likes").insert({
      comment_source: commentSource,
      comment_id: commentId,
      user_id: userId,
    })

    if (error?.code === UNIQUE_VIOLATION) {
      onMetaChange({
        count: Math.max(meta.count, 1),
        liked: true,
      })
      return true
    }

    if (error) {
      console.error("[comment-like] insert failed", error)
      onMetaChange(meta)
      return false
    }

    if (authorUserId) {
      await ensureLikeNotification(client, {
        recipientUserId: authorUserId,
        senderUserId: userId,
        target: buildCommentLikeNotificationTarget(
          commentId,
          commentSource,
          notificationParent
        ),
      })
    }

    return true
  } catch (err) {
    console.error("[comment-like] toggle failed", err)
    onMetaChange(meta)
    return false
  }
}

export function applyCommentLikeRealtimeEvent(
  previous: CommentLikeMeta,
  event: "INSERT" | "DELETE",
  actorUserId: string,
  currentUserId: string | null | undefined
): CommentLikeMeta {
  if (event === "INSERT") {
    if (actorUserId === currentUserId && previous.liked) {
      return previous
    }
    return {
      count: previous.count + 1,
      liked: actorUserId === currentUserId ? true : previous.liked,
    }
  }

  if (actorUserId === currentUserId && !previous.liked) {
    return previous
  }

  return {
    count: Math.max(0, previous.count - 1),
    liked: actorUserId === currentUserId ? false : previous.liked,
  }
}
