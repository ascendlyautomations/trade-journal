import { normalizeTradeFeedItem } from "@/app/components/feed/feedPostHelpers"
import type { FeaturedTradesWeekResponse } from "@/lib/featuredTradesWeek"
import {
  getFeaturedWeekStartIso,
  isPublicDiscoverableTradeRow,
  pickBestPnlPost,
  pickHighestRrPost,
} from "@/lib/featuredTradesWeekLogic"
import { getSupabaseServiceRole } from "@/lib/supabaseServiceRole"

/**
 * Same columns as FEED_POSTS_SELECT, but each relationship embedded once.
 * Avoids PostgREST 42712 from duplicate posts_trades / posts_profiles aliases.
 */
const FEATURED_POST_SELECT =
  "id, user_id, trade_id, created_at, pnl, rr, image_url, profiles!inner(username, avatar_url, is_private), trades!inner(created_at, public_description, user_id, ticker, direction, account_type, points, entry_time, exit_time, entry_price, exit_price, trade_date, duration_seconds, duration_text, is_public)"

const CANDIDATE_LIMIT = 12

async function fetchBestPnlPostServer() {
  const weekStart = getFeaturedWeekStartIso()
  const { data, error } = await getSupabaseServiceRole()
    .from("posts")
    .select(FEATURED_POST_SELECT)
    .eq("trades.is_public", true)
    .gte("created_at", weekStart)
    .order("pnl", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(CANDIDATE_LIMIT)

  if (error) {
    console.error("[featured-trades] best pnl query failed", error)
    return null
  }

  const row = pickBestPnlPost(
    (data ?? []).filter(isPublicDiscoverableTradeRow) as ReadonlyArray<{
      pnl?: unknown
      created_at?: string
    }>
  )
  return row ? normalizeTradeFeedItem(row as Record<string, unknown>) : null
}

async function fetchHighestRrPostServer() {
  const weekStart = getFeaturedWeekStartIso()
  const { data, error } = await getSupabaseServiceRole()
    .from("posts")
    .select(FEATURED_POST_SELECT)
    .eq("trades.is_public", true)
    .gte("created_at", weekStart)
    .not("rr", "is", null)
    .order("rr", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(CANDIDATE_LIMIT)

  if (error) {
    console.error("[featured-trades] highest rr query failed", error)
    return null
  }

  const row = pickHighestRrPost(
    (data ?? []).filter(isPublicDiscoverableTradeRow) as ReadonlyArray<{
      rr?: unknown
      created_at?: string
    }>
  )
  return row ? normalizeTradeFeedItem(row as Record<string, unknown>) : null
}

/** Server-side featured trades fetch — shared by homepage cache and API route. */
export async function fetchFeaturedTradesWeekServer(): Promise<FeaturedTradesWeekResponse> {
  const [bestPnlPost, highestRrPost] = await Promise.all([
    fetchBestPnlPostServer(),
    fetchHighestRrPostServer(),
  ])
  return { bestPnlPost, highestRrPost }
}
