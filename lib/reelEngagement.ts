import type { SupabaseClient } from "@supabase/supabase-js"
import { hapticLight } from "@/lib/nativeHaptics"
import { normalizeReelFeedItem } from "@/app/components/feed/feedPostHelpers"
import { FEED_REELS_SELECT } from "@/lib/reels"
import {
  DEMO_FEED_COMMENTS,
  DEMO_FEED_LIKES,
  findDemoFeedItem,
} from "@/lib/demo/demoFeed"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { ensureCommentNotificationsForInsert } from "./commentNotifications"
import {
  ensureLikeNotification,
  refreshLikeNotificationUi,
} from "./likeNotifications"

export type ReelLikeMeta = { count: number; liked: boolean }

const UNIQUE_VIOLATION = "23505"

export const REEL_COMMENT_CORE_SELECT =
  "id, reel_id, user_id, content, created_at, profiles(username, avatar_url)"

export const REEL_COMMENTS_SELECT =
  `${REEL_COMMENT_CORE_SELECT}, parent_comment_id, pinned`

export const REEL_COMMENT_INSERT_SELECT = REEL_COMMENT_CORE_SELECT

export { FEED_REELS_SELECT } from "@/lib/reels"

export function isReelFeedPost(
  post: { feedKind?: string; video_url?: unknown } | null | undefined
): boolean {
  if (post?.feedKind === "reel") return true
  const videoUrl = post?.video_url
  return videoUrl != null && String(videoUrl).trim() !== ""
}

export function reelOwnerUserId(post: {
  user_id?: string | null
}): string | null {
  const id = post.user_id
  if (id == null || String(id).trim() === "") return null
  return String(id)
}

function isMissingCommentSchemaColumn(error: {
  code?: string
  message?: string
} | null): boolean {
  if (!error) return false
  if (error.code === "PGRST204") return true
  const msg = (error.message ?? "").toLowerCase()
  return msg.includes("parent_comment_id") || msg.includes("pinned")
}

export async function queryReelComments<T extends { data: unknown; error: unknown }>(
  run: (select: string) => Promise<T>
): Promise<T> {
  const full = await run(REEL_COMMENTS_SELECT)
  if (
    !full.error ||
    !isMissingCommentSchemaColumn(full.error as { code?: string; message?: string })
  ) {
    return full
  }
  const withParent = await run(`${REEL_COMMENT_CORE_SELECT}, parent_comment_id`)
  if (
    !withParent.error ||
    !isMissingCommentSchemaColumn(
      withParent.error as { code?: string; message?: string }
    )
  ) {
    return withParent
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

  const demo = findDemoFeedItem(id, "reel")
  if (demo) return demo
  if (isDemoModeActive()) return null

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

/** Load like count + viewer liked state for one or more reels. */
export async function fetchReelLikeMetaByIds(
  client: SupabaseClient,
  reelIds: string[],
  currentUserId: string | null | undefined
): Promise<Record<string, ReelLikeMeta>> {
  const meta: Record<string, ReelLikeMeta> = {}
  for (const id of reelIds) {
    meta[id] = { count: 0, liked: false }
  }
  if (reelIds.length === 0) return meta

  if (isDemoModeActive()) {
    for (const id of reelIds) {
      meta[id] = DEMO_FEED_LIKES[id] ?? { count: 0, liked: false }
    }
    return meta
  }

  const { data, error } = await client
    .from("reel_likes")
    .select("reel_id, user_id")
    .in("reel_id", reelIds)

  if (error) {
    console.error("[reel-likes] fetch meta failed", error)
    return meta
  }

  for (const row of data ?? []) {
    const rid = String(row.reel_id)
    if (!meta[rid]) meta[rid] = { count: 0, liked: false }
    meta[rid].count++
    if (currentUserId && row.user_id === currentUserId) {
      meta[rid].liked = true
    }
  }

  return meta
}

/**
 * Toggle reel like with optimistic UI — mirrors achievement/profile post handlers.
 * Rolls back local state when the mutation fails (except unique-violation sync).
 */
export async function toggleReelLike(
  client: SupabaseClient,
  params: {
    reelId: string
    userId: string
    ownerUserId: string | null
    meta: ReelLikeMeta
    onMetaChange: (next: ReelLikeMeta) => void
  }
): Promise<boolean> {
  const reelId = params.reelId.trim()
  const { userId, ownerUserId, meta, onMetaChange } = params
  if (!reelId || !userId) return false

  const optimistic: ReelLikeMeta = meta.liked
    ? { count: Math.max(0, meta.count - 1), liked: false }
    : { count: meta.count + 1, liked: true }

  onMetaChange(optimistic)
  hapticLight("like")

  try {
    if (meta.liked) {
      const { error } = await client
        .from("reel_likes")
        .delete()
        .eq("reel_id", reelId)
        .eq("user_id", userId)

      if (error) {
        console.error("[reel-like] unlike failed", {
          reelId,
          userId,
          message: error.message,
          code: error.code,
        })
        onMetaChange(meta)
        return false
      }

      if (ownerUserId) {
        refreshLikeNotificationUi()
      }

      return true
    }

    const { error } = await client.from("reel_likes").insert({
      reel_id: reelId,
      user_id: userId,
    })

    if (error?.code === UNIQUE_VIOLATION) {
      const synced: ReelLikeMeta = {
        count: Math.max(meta.count, 1),
        liked: true,
      }
      onMetaChange(synced)
      return true
    }

    if (error) {
      console.error("[reel-like] insert failed", {
        reelId,
        userId,
        message: error.message,
        code: error.code,
        details: error.details,
        hint: error.hint,
      })
      onMetaChange(meta)
      return false
    }

    if (ownerUserId && ownerUserId !== userId) {
      await insertReelLikeNotification(client, {
        reelId,
        ownerUserId,
        senderUserId: userId,
      })
    }

    return true
  } catch (err) {
    console.error("[reel-like] toggle failed", err)
    onMetaChange(meta)
    return false
  }
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

  if (isDemoModeActive()) {
    for (const id of reelIds) {
      const likeMeta = DEMO_FEED_LIKES[id]
      likesMap[id] = likeMeta ?? { count: 0, liked: false }
      commentsMap[id] = DEMO_FEED_COMMENTS[id] ?? []
    }
    return { likesMap, commentsMap }
  }

  const [likeMetaById, commentsResult] = await Promise.all([
    fetchReelLikeMetaByIds(client, reelIds, currentUserId),
    queryReelComments((select) =>
      client
        .from("reel_comments")
        .select(select)
        .in("reel_id", reelIds)
        .order("created_at", { ascending: true })
    ),
  ])

  Object.assign(likesMap, likeMetaById)

  for (const c of (commentsResult.data as any[]) ?? []) {
    const rid = String(c.reel_id)
    if (!commentsMap[rid]) commentsMap[rid] = []
    commentsMap[rid].push(c)
  }

  return { likesMap, commentsMap }
}
