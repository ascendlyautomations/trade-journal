import type { SupabaseClient } from "@supabase/supabase-js"
import { writeTradeSocial } from "./tradeSocialCache.ts"

export type ProfileTradeEngagementMeta = {
  likes: number
  liked: boolean
  commentCount: number
}

const TRADE_COMMENT_PREVIEW_SELECT =
  "id, trade_id, user_id, content, created_at, profiles(username, avatar_url), parent_comment_id, pinned"

/**
 * Set-based trade engagement for Profile cards — replaces per-card trade_likes /
 * trade_comments fan-out (HAR Profile 1: 5 + 5 requests).
 */
export async function batchLoadProfileTradeEngagement(
  client: SupabaseClient,
  tradeIds: string[],
  viewerId: string | null | undefined,
  options?: { seedCommentPreviews?: boolean }
): Promise<Record<string, ProfileTradeEngagementMeta>> {
  const ids = [...new Set(tradeIds.map((id) => String(id).trim()).filter(Boolean))]
  const result: Record<string, ProfileTradeEngagementMeta> = {}
  for (const id of ids) {
    result[id] = { likes: 0, liked: false, commentCount: 0 }
  }
  if (ids.length === 0) return result

  const [likesRes, commentsRes] = await Promise.all([
    client.from("trade_likes").select("trade_id, user_id").in("trade_id", ids),
    options?.seedCommentPreviews
      ? client
          .from("trade_comments")
          .select(TRADE_COMMENT_PREVIEW_SELECT)
          .in("trade_id", ids)
          .order("created_at", { ascending: true })
      : client.from("trade_comments").select("trade_id").in("trade_id", ids),
  ])

  if (likesRes.error) {
    console.error("[profile] batch trade_likes:", likesRes.error.message)
  } else {
    for (const row of likesRes.data ?? []) {
      const tradeId = String((row as { trade_id: string }).trade_id)
      const meta = result[tradeId]
      if (!meta) continue
      meta.likes += 1
      if (viewerId && String((row as { user_id: string }).user_id) === viewerId) {
        meta.liked = true
      }
    }
  }

  const commentsByTrade: Record<string, unknown[]> = {}
  if (commentsRes.error) {
    console.error("[profile] batch trade_comments:", commentsRes.error.message)
  } else {
    for (const row of commentsRes.data ?? []) {
      const tradeId = String((row as { trade_id: string }).trade_id)
      const meta = result[tradeId]
      if (!meta) continue
      meta.commentCount += 1
      if (options?.seedCommentPreviews) {
        if (!commentsByTrade[tradeId]) commentsByTrade[tradeId] = []
        commentsByTrade[tradeId].push(row)
      }
    }
  }

  for (const [tradeId, meta] of Object.entries(result)) {
    writeTradeSocial(tradeId, {
      likes: meta.likes,
      liked: meta.liked,
      commentCount: meta.commentCount,
      comments: commentsByTrade[tradeId] ?? [],
    })
  }

  return result
}
