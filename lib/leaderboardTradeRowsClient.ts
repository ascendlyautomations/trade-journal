import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import { supabase } from "./supabaseClient.ts"
import { isDemoModeActive } from "./demo/demoMode.ts"
import { getDemoLeaderboardTrades } from "./demo/demoLeaderboard.ts"

const PAGE_SIZE = 1000

/** Authorized RPC scan (same rows as leaderboard aggregation). */
export async function fetchLeaderboardTradeRowsClient(
  maxRows = 3000
): Promise<TradeForLeaderboard[]> {
  if (isDemoModeActive()) {
    return getDemoLeaderboardTrades().slice(0, maxRows)
  }

  const capped = Math.max(1, Math.min(maxRows, 3000))
  const all: TradeForLeaderboard[] = []
  let afterCreatedAt: string | null = null
  let afterUserId: string | null = null

  while (all.length < capped) {
    const limit = Math.min(PAGE_SIZE, capped - all.length)
    const { data, error } = await supabase.rpc("leaderboard_trade_rows_page", {
      p_after_created_at: afterCreatedAt ?? undefined,
      p_after_user_id: afterUserId ?? undefined,
      p_limit: limit,
    })

    if (error) {
      console.error("[leaderboard] trade rows page client error:", error)
      break
    }

    const batch = (data ?? []) as TradeForLeaderboard[]
    if (batch.length === 0) break
    all.push(...batch)
    if (batch.length < limit) break

    const last = batch[batch.length - 1]
    afterCreatedAt = last.created_at
    afterUserId = last.user_id
  }

  return all
}
