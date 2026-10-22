import { normalizeTradeFeedItem } from "@/app/components/feed/feedPostHelpers"
import type { FeaturedTradesWeekResponse } from "@/lib/featuredTradesWeek"
import {
  featuredTradesPeriodHeading,
  resolveFeaturedTradesPeriod,
} from "@/lib/featuredTradesPeriodFallback.ts"
import {
  isPublicDiscoverableTradeRow,
  pickBestPnlPost,
  pickHighestRrPost,
} from "@/lib/featuredTradesWeekLogic"
import { getMondayOfWeek, startOfDay } from "@/lib/tradingReports/tradingReportPeriods"
import { getSupabaseServiceRole } from "@/lib/supabaseServiceRole"

/**
 * Same columns as FEED_POSTS_SELECT, but each relationship embedded once.
 * Avoids PostgREST 42712 from duplicate posts_trades / posts_profiles aliases.
 */
const FEATURED_POST_SELECT =
  "id, user_id, trade_id, created_at, pnl, rr, image_url, profiles!inner(username, avatar_url, is_private), trades!inner(created_at, public_description, user_id, ticker, direction, account_type, points, entry_time, exit_time, entry_price, exit_price, trade_date, duration_seconds, duration_text, is_public)"

const CANDIDATE_LIMIT = 400
const MAX_WEEK_LOOKBACK = 52

function featuredLookbackStartIso(now = new Date()): string {
  const thisMonday = getMondayOfWeek(startOfDay(now))
  const start = new Date(thisMonday)
  start.setDate(thisMonday.getDate() - 7 * MAX_WEEK_LOOKBACK)
  return start.toISOString()
}

function rowsInRange<T extends { created_at?: string }>(
  rows: readonly T[],
  start: Date,
  end: Date
): T[] {
  const startMs = start.getTime()
  const endMs = end.getTime()
  return rows.filter((row) => {
    if (!row.created_at) return false
    const ms = new Date(row.created_at).getTime()
    return ms >= startMs && ms <= endMs
  })
}

async function fetchFeaturedPostCandidates() {
  const since = featuredLookbackStartIso()
  const { data, error } = await getSupabaseServiceRole()
    .from("posts")
    .select(FEATURED_POST_SELECT)
    .eq("trades.is_public", true)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(CANDIDATE_LIMIT)

  if (error) {
    console.error("[featured-trades] candidate query failed", error)
    return []
  }

  return (data ?? []).filter(isPublicDiscoverableTradeRow) as ReadonlyArray<
    Record<string, unknown> & { pnl?: unknown; rr?: unknown; created_at?: string }
  >
}

const EMPTY_HEADING = {
  sectionTitle: "Featured Trades of the Week",
  sectionLead:
    "Discover some of the community's best trades from this calendar week.",
}

/** Server-side featured trades fetch — shared by homepage cache and API route. */
export async function fetchFeaturedTradesWeekServer(): Promise<FeaturedTradesWeekResponse> {
  const rows = await fetchFeaturedPostCandidates()
  const period = resolveFeaturedTradesPeriod(rows, rows)

  if (!period) {
    return {
      bestPnlPost: null,
      highestRrPost: null,
      ...EMPTY_HEADING,
      isHistoricalPeriod: false,
    }
  }

  const inPeriod = rowsInRange(rows, period.start, period.end)
  const bestPnlRow = pickBestPnlPost(inPeriod)
  const highestRrRow = pickHighestRrPost(inPeriod)
  const heading = featuredTradesPeriodHeading(period)

  return {
    bestPnlPost: bestPnlRow
      ? normalizeTradeFeedItem(bestPnlRow as Record<string, unknown>)
      : null,
    highestRrPost: highestRrRow
      ? normalizeTradeFeedItem(highestRrRow as Record<string, unknown>)
      : null,
    sectionTitle: heading.sectionTitle,
    sectionLead: heading.sectionLead,
    isHistoricalPeriod: period.kind !== "current_week",
  }
}
