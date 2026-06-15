import { NextResponse } from "next/server"
import { supabaseServiceRole } from "../../_lib/getRouteUser"
import type { TradeForLeaderboard } from "@/lib/leaderboardChart"

const PAGE_SIZE = 1000

async function fetchViaRpc(): Promise<TradeForLeaderboard[] | null> {
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
      console.error("[api/leaderboard/trades] rpc error:", error)
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
  let from = 0

  while (true) {
    const { data, error } = await supabaseServiceRole
      .from("trades")
      .select("user_id, pnl, rr, created_at, account_type, mode")
      .order("created_at", { ascending: true })
      .range(from, from + PAGE_SIZE - 1)

    if (error) {
      console.error("[api/leaderboard/trades] trades error:", error)
      break
    }

    const batch = ((data || []) as TradeForLeaderboard[]).filter((t) =>
      publicUserIds.has(t.user_id)
    )
    allTrades.push(...batch)

    if (!data || data.length < PAGE_SIZE) break
    from += PAGE_SIZE
  }

  return allTrades
}

/** Aggregated leaderboard inputs: all trades from public-profile users only. */
export async function GET() {
  const trades = (await fetchViaRpc()) ?? (await fetchViaJoin())
  return NextResponse.json(trades)
}
