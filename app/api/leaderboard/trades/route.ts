import { NextResponse } from "next/server"
import { unstable_cache } from "next/cache"
import { supabaseServiceRole } from "../../_lib/getRouteUser"
import type { TradeForLeaderboard } from "@/lib/leaderboardChart"

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

const getCachedLeaderboardTrades = unstable_cache(
  loadLeaderboardTradesUncached,
  ["leaderboard-trade-rows-v1"],
  { revalidate: LEADERBOARD_TRADES_REVALIDATE_SECONDS }
)

/** Aggregated leaderboard inputs: public trades from public-profile users only. */
export async function GET() {
  const trades = await getCachedLeaderboardTrades()
  return NextResponse.json(trades)
}
