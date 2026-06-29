import type { SupabaseClient } from "@supabase/supabase-js"
import { normalizeReelFeedItem } from "@/app/components/feed/feedPostHelpers"
import { ensureCommentNotificationsForInsert } from "./commentNotifications"
import { ensureLikeNotification } from "./likeNotifications"

export const REEL_COMMENT_CORE_SELECT =
  "id, reel_id, user_id, content, created_at, profiles(username, avatar_url)"

export const REEL_COMMENTS_SELECT =
  `${REEL_COMMENT_CORE_SELECT}, parent_comment_id`

export const REEL_COMMENT_INSERT_SELECT = REEL_COMMENT_CORE_SELECT

export const FEED_REELS_SELECT =
  "id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, created_at, profiles(username, avatar_url)"

export function isReelFeedPost(
  post: { feedKind?: string } | null | undefined
): boolean {
  return post?.feedKind === "reel"
}

export function reelOwnerUserId(post: {
  user_id?: string | null
}): string | null {
  const id = post.user_id
  if (id == null || String(id).trim() === "") return null
  return String(id)
}

function isMissingParentCommentIdColumn(error: {
  code?: string
  message?: string
} | null): boolean {
  if (!error) return false
  if (error.code === "PGRST204") return true
  const msg = (error.message ?? "").toLowerCase()
  return msg.includes("parent_comment_id")
}

export async function queryReelComments<T extends { data: unknown; error: unknown }>(
  run: (select: string) => Promise<T>
): Promise<T> {
  const full = await run(REEL_COMMENTS_SELECT)
  if (
    !full.error ||
    !isMissingParentCommentIdColumn(full.error as { code?: string; message?: string })
  ) {
    return full
  }
  return run(REEL_COMMENT_CORE_SELECT)
}

export function withInsertedReelParentCommentId<T extends Record<string, unknown>>(
  row: T,
  parentCommentId?: string | null
): T & { parent_comment_id?: string | null } {
  if (!parentCommentId) return row
  return { ...row, parent_comment_id: parentCommentId }
}

export async function fetchReelFeedPostById(
  client: SupabaseClient,
  reelId: string
) {
  const id = reelId.trim()
  if (!id) return null

  const { data, error } = await client
    .from("reels")
    .select(FEED_REELS_SELECT)
    .eq("id", id)
    .maybeSingle()

  if (error) {
    console.error("fetchReelFeedPostById:", error)
    return null
  }

  if (!data) return null
  return normalizeReelFeedItem(data as Record<string, unknown>)
}

export async function insertReelLikeNotification(
  supabase: SupabaseClient,
  params: {
    reelId: string
    ownerUserId: string
    senderUserId: string
  }
) {
  await ensureLikeNotification(supabase, {
    recipientUserId: params.ownerUserId,
    senderUserId: params.senderUserId,
    target: { kind: "reel", reelId: params.reelId },
  })
}

export async function insertReelCommentNotifications(
  client: SupabaseClient,
  params: {
    reelId: string
    commentId: string
    senderUserId: string
    content: string
    ownerUserId: string
    parentCommentId?: string | null
    existingComments?: Array<{ id: string; user_id: string }>
  }
) {
  await ensureCommentNotificationsForInsert(client, {
    commentId: params.commentId,
    senderUserId: params.senderUserId,
    content: params.content,
    target: { kind: "reel", reelId: params.reelId },
    ownerUserId: params.ownerUserId,
    parentCommentId: params.parentCommentId,
    existingComments: params.existingComments,
  })
}

export type ReelEngagementMaps = {
  likesMap: Record<string, { count: number; liked: boolean }>
  commentsMap: Record<string, any[]>
}

export async function loadReelEngagementMaps(
  client: SupabaseClient,
  reelIds: string[],
  currentUserId: string | null | undefined
): Promise<ReelEngagementMaps> {
  const likesMap: Record<string, { count: number; liked: boolean }> = {}
  const commentsMap: Record<string, any[]> = {}

  for (const id of reelIds) {
    likesMap[id] = { count: 0, liked: false }
    commentsMap[id] = []
  }

  if (reelIds.length === 0) {
    return { likesMap, commentsMap }
  }

  const [{ data: likeRows }, commentsResult] = await Promise.all([
    client
      .from("reel_likes")
      .select("reel_id, user_id")
      .in("reel_id", reelIds),
    queryReelComments((select) =>
      client
        .from("reel_comments")
        .select(select)
        .in("reel_id", reelIds)
        .order("created_at", { ascending: true })
    ),
  ])

  for (const row of likeRows ?? []) {
    const rid = String(row.reel_id)
    if (!likesMap[rid]) likesMap[rid] = { count: 0, liked: false }
    likesMap[rid].count++
    if (currentUserId && row.user_id === currentUserId) {
      likesMap[rid].liked = true
    }
  }

  for (const c of (commentsResult.data as any[]) ?? []) {
    const rid = String(c.reel_id)
    if (!commentsMap[rid]) commentsMap[rid] = []
    commentsMap[rid].push(c)
  }

  return { likesMap, commentsMap }
}
