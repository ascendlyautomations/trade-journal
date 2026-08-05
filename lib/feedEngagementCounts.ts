import type { SupabaseClient } from "@supabase/supabase-js"

export type FeedEngagementLikeMeta = {
  count: number
  liked: boolean
}

export type FeedEngagementMaps = {
  likesMap: Record<string, FeedEngagementLikeMeta>
  commentCountsMap: Record<string, number>
}

type FeedEngagementRpcRow = {
  content_type: string
  content_id: string
  like_count: number | string
  comment_count: number | string
  liked_by_me: boolean
}

function isMissingRpc(error: { code?: string; message?: string }): boolean {
  const message = String(error.message ?? "").toLowerCase()
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    message.includes("could not find the function") ||
    message.includes("schema cache")
  )
}

function emptyMapsForIds(ids: string[]): FeedEngagementMaps {
  const likesMap: Record<string, FeedEngagementLikeMeta> = {}
  const commentCountsMap: Record<string, number> = {}
  for (const id of ids) {
    likesMap[id] = { count: 0, liked: false }
    commentCountsMap[id] = 0
  }
  return { likesMap, commentCountsMap }
}

/** Legacy path: fetch all engagement rows and count in JS (pre-RPC). */
async function fetchFeedEngagementViaRowScan(
  client: SupabaseClient,
  params: {
    tradeIds: string[]
    profileIds: string[]
    achievementIds: string[]
    reelIds: string[]
    seedIds: string[]
    currentUserId: string | null | undefined
  }
): Promise<FeedEngagementMaps> {
  const { likesMap, commentCountsMap } = emptyMapsForIds(params.seedIds)

  const [
    { data: tradeLikesRows },
    { data: tradeCommentsRows },
    { data: profileLikesRows },
    { data: profileCommentsRows },
    { data: achievementLikesRows },
    { data: achievementCommentsRows },
    { data: reelLikesRows },
    { data: reelCommentsRows },
  ] = await Promise.all([
    params.tradeIds.length
      ? client.from("likes").select("post_id, user_id").in("post_id", params.tradeIds)
      : Promise.resolve({ data: [] as { post_id: string; user_id: string }[] }),
    params.tradeIds.length
      ? client.from("comments").select("post_id").in("post_id", params.tradeIds)
      : Promise.resolve({ data: [] as { post_id: string }[] }),
    params.profileIds.length
      ? client
          .from("profile_post_likes")
          .select("profile_post_id, user_id")
          .in("profile_post_id", params.profileIds)
      : Promise.resolve({
          data: [] as { profile_post_id: string; user_id: string }[],
        }),
    params.profileIds.length
      ? client
          .from("profile_post_comments")
          .select("profile_post_id")
          .in("profile_post_id", params.profileIds)
      : Promise.resolve({ data: [] as { profile_post_id: string }[] }),
    params.achievementIds.length
      ? client
          .from("achievement_post_likes")
          .select("achievement_post_id, user_id")
          .in("achievement_post_id", params.achievementIds)
      : Promise.resolve({
          data: [] as { achievement_post_id: string; user_id: string }[],
        }),
    params.achievementIds.length
      ? client
          .from("achievement_post_comments")
          .select("achievement_post_id")
          .in("achievement_post_id", params.achievementIds)
      : Promise.resolve({ data: [] as { achievement_post_id: string }[] }),
    params.reelIds.length
      ? client
          .from("reel_likes")
          .select("reel_id, user_id")
          .in("reel_id", params.reelIds)
      : Promise.resolve({ data: [] as { reel_id: string; user_id: string }[] }),
    params.reelIds.length
      ? client.from("reel_comments").select("reel_id").in("reel_id", params.reelIds)
      : Promise.resolve({ data: [] as { reel_id: string }[] }),
  ])

  const applyLike = (id: string, userId: string) => {
    if (!likesMap[id]) likesMap[id] = { count: 0, liked: false }
    likesMap[id].count++
    if (params.currentUserId && userId === params.currentUserId) {
      likesMap[id].liked = true
    }
  }
  const applyComment = (id: string) => {
    commentCountsMap[id] = (commentCountsMap[id] ?? 0) + 1
  }

  for (const row of tradeLikesRows || []) {
    applyLike(String(row.post_id), String(row.user_id))
  }
  for (const row of profileLikesRows || []) {
    applyLike(String(row.profile_post_id), String(row.user_id))
  }
  for (const row of achievementLikesRows || []) {
    applyLike(String(row.achievement_post_id), String(row.user_id))
  }
  for (const row of reelLikesRows || []) {
    applyLike(String(row.reel_id), String(row.user_id))
  }
  for (const row of tradeCommentsRows || []) {
    applyComment(String(row.post_id))
  }
  for (const row of profileCommentsRows || []) {
    applyComment(String(row.profile_post_id))
  }
  for (const row of achievementCommentsRows || []) {
    applyComment(String(row.achievement_post_id))
  }
  for (const row of reelCommentsRows || []) {
    applyComment(String(row.reel_id))
  }

  return { likesMap, commentCountsMap }
}

/**
 * Load like/comment counts + liked-by-me for feed cards.
 * Prefers aggregate RPC; falls back to legacy row scan if RPC is unavailable.
 */
export async function fetchFeedEngagementMaps(
  client: SupabaseClient,
  params: {
    tradeIds: string[]
    profileIds: string[]
    achievementIds: string[]
    reelIds: string[]
    /** IDs that must appear in maps even with zero engagement (usually post ids). */
    seedIds: string[]
    currentUserId: string | null | undefined
  }
): Promise<FeedEngagementMaps> {
  const { likesMap, commentCountsMap } = emptyMapsForIds(params.seedIds)

  const hasAny =
    params.tradeIds.length > 0 ||
    params.profileIds.length > 0 ||
    params.achievementIds.length > 0 ||
    params.reelIds.length > 0

  if (!hasAny) return { likesMap, commentCountsMap }

  const { data, error } = await client.rpc("feed_engagement_counts", {
    p_post_ids: params.tradeIds,
    p_profile_post_ids: params.profileIds,
    p_achievement_post_ids: params.achievementIds,
    p_reel_ids: params.reelIds,
  })

  if (error) {
    if (isMissingRpc(error)) {
      return fetchFeedEngagementViaRowScan(client, params)
    }
    console.error("[feed] engagement counts RPC:", error)
    return { likesMap, commentCountsMap }
  }

  for (const row of (data ?? []) as FeedEngagementRpcRow[]) {
    const id = String(row.content_id)
    likesMap[id] = {
      count: Number(row.like_count) || 0,
      liked: row.liked_by_me === true,
    }
    commentCountsMap[id] = Number(row.comment_count) || 0
  }

  return { likesMap, commentCountsMap }
}
