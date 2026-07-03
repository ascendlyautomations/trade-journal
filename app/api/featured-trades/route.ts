import { NextResponse } from "next/server"
import { normalizeTradeFeedItem } from "@/app/components/feed/feedPostHelpers"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  getFeaturedWeekStartIso,
  isPublicDiscoverableTradeRow,
  pickBestPnlPost,
  pickHighestRrPost,
} from "@/lib/featuredTradesWeekLogic"
import type { FeaturedTradesWeekResponse } from "@/lib/featuredTradesWeek"

/**
 * Same columns as FEED_POSTS_SELECT, but each relationship embedded once.
 * Avoids PostgREST 42712 from duplicate posts_trades / posts_profiles aliases
 * (FEED_POSTS_SELECT already embeds trades(...) and profiles(...)).
 */
const FEATURED_POST_SELECT =
  "id, user_id, trade_id, created_at, pnl, rr, image_url, profiles!inner(username, avatar_url, is_private), trades!inner(created_at, public_description, user_id, ticker, direction, account_type, points, entry_time, exit_time, entry_price, exit_price, trade_date, duration_seconds, duration_text, is_public)"
/** Small candidate pool so we can skip private-profile rows without scanning the full feed. */
const CANDIDATE_LIMIT = 12

function logFeaturedQuery(label: string, filters: Record<string, unknown>) {
  console.log("[api/featured-trades] query", {
    label,
    select: FEATURED_POST_SELECT,
    ...filters,
  })
}

async function fetchBestPnlPost() {
  const weekStart = getFeaturedWeekStartIso()
  logFeaturedQuery("best-pnl", {
    filters: { "trades.is_public": true, created_at_gte: weekStart },
    order: ["pnl desc", "created_at desc"],
    limit: CANDIDATE_LIMIT,
  })
  const { data, error } = await supabaseServiceRole
    .from("posts")
    .select(FEATURED_POST_SELECT)
    .eq("trades.is_public", true)
    .gte("created_at", weekStart)
    .order("pnl", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(CANDIDATE_LIMIT)

  if (error) {
    console.error("[api/featured-trades] best pnl query failed", error)
    return null
  }

  const row = pickBestPnlPost((data ?? []).filter(isPublicDiscoverableTradeRow))
  return row ? normalizeTradeFeedItem(row as Record<string, unknown>) : null
}

async function fetchHighestRrPost() {
  const weekStart = getFeaturedWeekStartIso()
  logFeaturedQuery("highest-rr", {
    filters: { "trades.is_public": true, created_at_gte: weekStart, rr_not_null: true },
    order: ["rr desc", "created_at desc"],
    limit: CANDIDATE_LIMIT,
  })
  const { data, error } = await supabaseServiceRole
    .from("posts")
    .select(FEATURED_POST_SELECT)
    .eq("trades.is_public", true)
    .gte("created_at", weekStart)
    .not("rr", "is", null)
    .order("rr", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(CANDIDATE_LIMIT)

  if (error) {
    console.error("[api/featured-trades] highest rr query failed", error)
    return null
  }

  const row = pickHighestRrPost((data ?? []).filter(isPublicDiscoverableTradeRow))
  return row ? normalizeTradeFeedItem(row as Record<string, unknown>) : null
}

export async function GET() {
  const [bestPnlPost, highestRrPost] = await Promise.all([
    fetchBestPnlPost(),
    fetchHighestRrPost(),
  ])

  const response: FeaturedTradesWeekResponse = {
    bestPnlPost,
    highestRrPost,
  }

  return NextResponse.json(response, {
    headers: {
      "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600",
    },
  })
}
