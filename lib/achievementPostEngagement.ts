import type { SupabaseClient } from "@supabase/supabase-js"
import type { Achievement } from "@/lib/achievements"
import { normalizeAchievementFeedItem } from "@/app/components/feed/feedPostHelpers"
import {
  DEMO_FEED_COMMENTS,
  DEMO_FEED_LIKES,
  findDemoFeedItem,
  getDemoAchievementPostIdsByAchievementIds,
} from "@/lib/demo/demoFeed"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { ensureCommentNotificationsForInsert } from "./commentNotifications"
import { ensureLikeNotification } from "./likeNotifications"

export const ACHIEVEMENT_POST_COMMENT_CORE_SELECT =
  "id, achievement_post_id, user_id, content, created_at, profiles(username, avatar_url)"

export const ACHIEVEMENT_POST_COMMENTS_SELECT =
  `${ACHIEVEMENT_POST_COMMENT_CORE_SELECT}, parent_comment_id`

export const ACHIEVEMENT_POST_COMMENT_INSERT_SELECT =
  ACHIEVEMENT_POST_COMMENT_CORE_SELECT

export const FEED_ACHIEVEMENT_POSTS_SELECT =
  "id, user_id, achievement_id, created_at, metadata, achievements(id, title, description, achievement_type, badge_key, tier, value_text, value_numeric, currency, image_url, achieved_at, is_public, is_featured, category, firm, metadata), profiles(username, avatar_url)"

export function isAchievementFeedPost(
  post: { feedKind?: string } | null | undefined
): boolean {
  return post?.feedKind === "achievement"
}

export function achievementFromPost(post: any): Achievement {
  const row = post.achievements ?? {}
  return {
    id: String(row.id ?? post.achievement_id ?? post.id),
    user_id: String(post.user_id),
    achievement_type: String(row.achievement_type ?? "milestone"),
    title: String(row.title ?? "Achievement"),
    description: row.description != null ? String(row.description) : null,
    badge_key: row.badge_key != null ? String(row.badge_key) : null,
    tier: row.tier != null ? String(row.tier) : null,
    category: row.category != null ? String(row.category) : null,
    value_numeric:
      row.value_numeric != null && row.value_numeric !== ""
        ? Number(row.value_numeric)
        : null,
    value_text: row.value_text != null ? String(row.value_text) : null,
    currency: row.currency != null ? String(row.currency) : null,
    account_type: null,
    account_name: null,
    account_size: null,
    mode: null,
    firm: row.firm != null ? String(row.firm) : null,
    image_url: row.image_url != null ? String(row.image_url) : null,
    achieved_at: row.achieved_at != null ? String(row.achieved_at) : null,
    created_at: post.created_at != null ? String(post.created_at) : null,
    updated_at: null,
    is_featured: Boolean(row.is_featured),
    is_public: row.is_public !== false,
    sort_order: null,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
  }
}

export async function fetchAchievementPostById(
  client: SupabaseClient,
  postId: string
) {
  const id = postId.trim()
  if (!id) return null

  const demo = findDemoFeedItem(id, "achievement")
  if (demo) return demo
  if (isDemoModeActive()) return null

  const { data, error } = await client
    .from("achievement_posts")
    .select(FEED_ACHIEVEMENT_POSTS_SELECT)
    .eq("id", id)
    .maybeSingle()

  if (error) {
    console.error("fetchAchievementPostById:", error)
    return null
  }

  if (!data) return null

  return normalizeAchievementFeedItem(data as Record<string, unknown>)
}

export function achievementPostOwnerUserId(post: {
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

export async function queryAchievementPostComments<
  T extends { data: unknown; error: unknown },
>(run: (select: string) => Promise<T>): Promise<T> {
  const full = await run(ACHIEVEMENT_POST_COMMENTS_SELECT)
  if (
    !full.error ||
    !isMissingParentCommentIdColumn(full.error as { code?: string; message?: string })
  ) {
    return full
  }
  return run(ACHIEVEMENT_POST_COMMENT_CORE_SELECT)
}

export function withInsertedAchievementPostParentCommentId<
  T extends Record<string, unknown>,
>(row: T, parentCommentId?: string | null): T & { parent_comment_id?: string | null } {
  if (!parentCommentId) return row
  return { ...row, parent_comment_id: parentCommentId }
}

export async function fetchAchievementPostIdsByAchievementIds(
  client: SupabaseClient,
  achievementIds: string[]
): Promise<Record<string, string>> {
  const ids = [...new Set(achievementIds.map((id) => id.trim()).filter(Boolean))]
  if (ids.length === 0) return {}

  if (isDemoModeActive()) {
    return getDemoAchievementPostIdsByAchievementIds(ids)
  }

  const { data, error } = await client
    .from("achievement_posts")
    .select("id, achievement_id")
    .in("achievement_id", ids)

  if (error) {
    console.error("fetchAchievementPostIdsByAchievementIds:", error)
    return {}
  }

  const map: Record<string, string> = {}
  for (const row of data ?? []) {
    map[String(row.achievement_id)] = String(row.id)
  }
  return map
}

export async function insertAchievementPostLikeNotification(
  client: SupabaseClient,
  params: {
    achievementPostId: string
    ownerUserId: string
    senderUserId: string
  }
) {
  await ensureLikeNotification(client, {
    recipientUserId: params.ownerUserId,
    senderUserId: params.senderUserId,
    target: {
      kind: "achievement_post",
      achievementPostId: params.achievementPostId,
    },
  })
}

export async function insertAchievementPostCommentNotifications(
  client: SupabaseClient,
  params: {
    achievementPostId: string
    commentId: string
    ownerUserId: string
    senderUserId: string
    content: string
    parentCommentId?: string | null
    existingComments?: Array<{ id: string; user_id: string }>
  }
) {
  await ensureCommentNotificationsForInsert(client, {
    commentId: params.commentId,
    senderUserId: params.senderUserId,
    content: params.content,
    target: {
      kind: "achievement_post",
      achievementPostId: params.achievementPostId,
    },
    ownerUserId: params.ownerUserId,
    parentCommentId: params.parentCommentId,
    existingComments: params.existingComments,
  })
}

export type AchievementEngagementMaps = {
  likesMap: Record<string, { count: number; liked: boolean }>
  commentsMap: Record<string, any[]>
}

export async function loadAchievementPostEngagementMaps(
  client: SupabaseClient,
  postIds: string[],
  currentUserId: string | null | undefined
): Promise<AchievementEngagementMaps> {
  const likesMap: Record<string, { count: number; liked: boolean }> = {}
  const commentsMap: Record<string, any[]> = {}

  for (const id of postIds) {
    likesMap[id] = { count: 0, liked: false }
    commentsMap[id] = []
  }

  if (postIds.length === 0) {
    return { likesMap, commentsMap }
  }

  if (isDemoModeActive()) {
    for (const id of postIds) {
      likesMap[id] = DEMO_FEED_LIKES[id] ?? { count: 0, liked: false }
      commentsMap[id] = [...(DEMO_FEED_COMMENTS[id] ?? [])]
    }
    return { likesMap, commentsMap }
  }

  const [{ data: likeRows }, commentsResult] = await Promise.all([
    client
      .from("achievement_post_likes")
      .select("achievement_post_id, user_id")
      .in("achievement_post_id", postIds),
    queryAchievementPostComments((select) =>
      client
        .from("achievement_post_comments")
        .select(select)
        .in("achievement_post_id", postIds)
        .order("created_at", { ascending: true })
    ),
  ])

  for (const row of likeRows ?? []) {
    const pid = String(row.achievement_post_id)
    if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
    likesMap[pid].count++
    if (currentUserId && row.user_id === currentUserId) {
      likesMap[pid].liked = true
    }
  }

  for (const c of (commentsResult.data as any[]) ?? []) {
    const pid = String(c.achievement_post_id)
    if (!commentsMap[pid]) commentsMap[pid] = []
    commentsMap[pid].push(c)
  }

  return { likesMap, commentsMap }
}
