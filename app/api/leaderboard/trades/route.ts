import { NextResponse } from "next/server"
import { unstable_cache } from "next/cache"
import { supabaseServiceRole } from "../../_lib/getRouteUser"
import type { TradeForLeaderboard } from "@/lib/leaderboardChart"
import {
  buildLeaderboardPayloadFromTrades,
  leaderboardCacheNowBucket,
  leaderboardCustomInstants,
  normalizeLeaderboardPayload,
  parseLeaderboardAccount,
  parseLeaderboardView,
  type LeaderboardPayload,
  type LeaderboardQuery,
} from "@/lib/leaderboardAggregate"

const PAGE_SIZE = 1000
/** Soft TTL — rankings refresh on next miss; filter UX stays client-side. */
const LEADERBOARD_TRADES_REVALIDATE_SECONDS = 60

async function fetchViaKeysetRpc(): Promise<TradeForLeaderboard[] | null> {
  const allTrades: TradeForLeaderboard[] = []
  let afterCreatedAt: string | null = null
  let afterUserId: string | null = null

  while (true) {
    const { data, error } = await supabaseServiceRole.rpc(
      "leaderboard_trade_rows_page",
      {
        p_after_created_at: afterCreatedAt ?? undefined,
        p_after_user_id: afterUserId ?? undefined,
        p_limit: PAGE_SIZE,
      }
    )

    if (error) {
      if (
        error.code === "PGRST202" ||
        error.message?.includes("leaderboard_trade_rows_page")
      ) {
        return null
      }
      console.error("[api/leaderboard/trades] keyset rpc error:", error)
      return null
    }

    const batch = (data || []) as TradeForLeaderboard[]
    allTrades.push(...batch)
    if (batch.length < PAGE_SIZE) break

    const last = batch[batch.length - 1]
    afterCreatedAt = last.created_at
    afterUserId = last.user_id
  }

  return allTrades
}

async function fetchViaOffsetRpc(): Promise<TradeForLeaderboard[] | null> {
  const allTrades: TradeForLeaderboard[] = []
  let offset = 0

  while (true) {
    const { data, error } = await supabaseServiceRole.rpc("leaderboard_trade_rows", {
      p_offset: offset,
      p_limit: PAGE_SIZE,
    })

    if (error) {
      if (
        error.code === "PGRST202" ||
        error.message?.includes("leaderboard_trade_rows")
      ) {
        return null
      }
      console.error("[api/leaderboard/trades] offset rpc error:", error)
      return null
    }

    const batch = (data || []) as TradeForLeaderboard[]
    allTrades.push(...batch)
    if (batch.length < PAGE_SIZE) break
    offset += PAGE_SIZE
  }

  return allTrades
}

async function fetchViaJoin(): Promise<TradeForLeaderboard[]> {
  const { data: profiles, error: profileError } = await supabaseServiceRole
    .from("profiles")
    .select("id, is_private")

  if (profileError) {
    console.error("[api/leaderboard/trades] profile error:", profileError)
    return []
  }

  const publicUserIds = new Set(
    (profiles || [])
      .filter((p) => p.is_private !== true)
      .map((p) => String(p.id))
  )

  const allTrades: TradeForLeaderboard[] = []
  let afterCreatedAt: string | null = null
  let afterUserId: string | null = null

  while (true) {
    let query = supabaseServiceRole
      .from("trades")
      .select("user_id, pnl, rr, created_at, account_type, mode")
      .eq("is_public", true)
      .order("created_at", { ascending: true })
      .order("user_id", { ascending: true })
      .limit(PAGE_SIZE)

    if (afterCreatedAt && afterUserId) {
      // Keyset: (created_at, user_id) > cursor
      query = query.or(
        `created_at.gt.${afterCreatedAt},and(created_at.eq.${afterCreatedAt},user_id.gt.${afterUserId})`
      )
    }

    const { data, error } = await query

    if (error) {
      console.error("[api/leaderboard/trades] trades error:", error)
      break
    }

    const raw = (data || []) as TradeForLeaderboard[]
    const batch = raw.filter((t) => publicUserIds.has(t.user_id))
    allTrades.push(...batch)

    if (raw.length < PAGE_SIZE) break
    const last = raw[raw.length - 1]
    afterCreatedAt = last.created_at
    afterUserId = last.user_id
  }

  return allTrades
}

async function loadLeaderboardTradesUncached(): Promise<TradeForLeaderboard[]> {
  return (
    (await fetchViaKeysetRpc()) ??
    (await fetchViaOffsetRpc()) ??
    (await fetchViaJoin())
  )
}

function isMissingRankedRpc(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false
  return (
    error.code === "PGRST202" ||
    (error.message ?? "").includes("leaderboard_ranked_window")
  )
}

async function loadRankedPayload(query: LeaderboardQuery): Promise<LeaderboardPayload> {
  const custom =
    query.customStartIso && query.customEndIso
      ? { startIso: query.customStartIso, endIso: query.customEndIso }
      : leaderboardCustomInstants(query.customStartYmd ?? "", query.customEndYmd ?? "")
  const { data, error } = await supabaseServiceRole.rpc("leaderboard_ranked_window", {
    p_view: query.view,
    p_account_type: query.accountType,
    p_now: query.nowIso,
    p_custom_start: custom?.startIso,
    p_custom_end: custom?.endIso,
    p_custom_start_ymd: query.customStartYmd || undefined,
    p_custom_end_ymd: query.customEndYmd || undefined,
    p_viewer_id: query.viewerId || undefined,
    p_rank_limit: 25,
  })

  if (!error) {
    const payload = normalizeLeaderboardPayload(data)
    if (payload) return payload
  } else if (!isMissingRankedRpc(error)) {
    console.error("[api/leaderboard/trades] ranked rpc error:", error)
    throw new Error(error.message)
  }

  // Migration not applied yet: aggregate on the server. Still do not return raw trades.
  const trades = await loadLeaderboardTradesUncached()
  return buildLeaderboardPayloadFromTrades(trades, query)
}

const getCachedRankedPayload = unstable_cache(
  async (serializedQuery: string) =>
    loadRankedPayload(JSON.parse(serializedQuery) as LeaderboardQuery),
  ["leaderboard-ranked-v2"],
  { revalidate: LEADERBOARD_TRADES_REVALIDATE_SECONDS }
)

/** Ranked leaderboard window. The browser does not receive raw trades. */
export async function GET(req: Request) {
  const url = new URL(req.url)
  const nowIso = url.searchParams.get("now") || new Date().toISOString()
  const query: LeaderboardQuery = {
    view: parseLeaderboardView(url.searchParams.get("view")),
    accountType: parseLeaderboardAccount(url.searchParams.get("account")),
    nowIso: new Date(
      Number(leaderboardCacheNowBucket(nowIso)) * 60_000
    ).toISOString(),
    customStartYmd: url.searchParams.get("customStart") ?? "",
    customEndYmd: url.searchParams.get("customEnd") ?? "",
    customStartIso: url.searchParams.get("customStartAt") ?? "",
    customEndIso: url.searchParams.get("customEndAt") ?? "",
    viewerId: url.searchParams.get("viewer") || null,
  }
  const payload = await getCachedRankedPayload(JSON.stringify(query))
  return NextResponse.json(payload)
}
