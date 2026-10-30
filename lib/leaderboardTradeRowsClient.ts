import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import { supabase } from "./supabaseClient.ts"
import { isDemoModeActive } from "./demo/demoMode.ts"
import { getDemoLeaderboardTrades } from "./demo/demoLeaderboard.ts"
import {
  paginateLeaderboardTradeRows,
  LEADERBOARD_TRADE_ROWS_MAX,
} from "./leaderboardTradeRowsPaginate.ts"

/** Authorized RPC scan (same rows as leaderboard aggregation). */
export async function fetchLeaderboardTradeRowsClient(
  maxRows = LEADERBOARD_TRADE_ROWS_MAX
): Promise<TradeForLeaderboard[]> {
  if (isDemoModeActive()) {
    return getDemoLeaderboardTrades().slice(0, maxRows)
  }

  const { trades } = await paginateLeaderboardTradeRows(supabase, {
    maxRows,
    operation: "leaderboard_trade_rows_client",
  })
  return trades
}
