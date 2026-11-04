import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  hasFeaturedPostImage,
  isPublicDiscoverableTradeRow,
} from "./featuredTradesWeekLogic.ts"
import { getMondayOfWeek, startOfDay } from "./tradingReports/tradingReportPeriods.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"
import { serviceRoleTableRead } from "./supabaseServiceTableRead.ts"

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

export type FeaturedPostCandidate = Record<string, unknown> & {
  pnl?: unknown
  rr?: unknown
  created_at?: string
}

export async function fetchFeaturedPostCandidates(options?: {
  client?: SupabaseClient<Database>
  timeoutMs?: number
}): Promise<readonly FeaturedPostCandidate[]> {
  const since = featuredLookbackStartIso()
  const db = options?.client ?? getSupabaseServiceRole()
  try {
    const data = await serviceRoleTableRead(
      db,
      "featured_trades_candidates",
      async (signal) => {
        const result = await db
          .from("posts")
          .select(FEATURED_POST_SELECT)
          .eq("trades.is_public", true)
          .gte("created_at", since)
          .order("created_at", { ascending: false })
          .limit(CANDIDATE_LIMIT)
          .abortSignal(signal)
        return { data: result.data, error: result.error }
      },
      { timeoutMs: options?.timeoutMs }
    )
    return (data ?? []).filter(
      (row) => isPublicDiscoverableTradeRow(row) && hasFeaturedPostImage(row)
    ) as FeaturedPostCandidate[]
  } catch (error) {
    console.error("[featured-trades] candidate query failed", error)
    return []
  }
}
