import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import {
  paginateLeaderboardTradeRows,
  LEADERBOARD_TRADE_ROWS_MAX,
} from "./leaderboardTradeRowsPaginate.ts"
import {
  leaderboardTradeRowsFlightKey,
  withLeaderboardTradeRowsSingleFlight,
} from "./leaderboardTradeRowsSingleFlight.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"

/** Service-role scan of public leaderboard trade rows (homepage SSR). */
export async function fetchLeaderboardTradeRowsServer(
  maxRows = LEADERBOARD_TRADE_ROWS_MAX
): Promise<TradeForLeaderboard[]> {
  const capped = Math.max(1, Math.min(maxRows, LEADERBOARD_TRADE_ROWS_MAX))
  const flightKey = leaderboardTradeRowsFlightKey(capped)

  return withLeaderboardTradeRowsSingleFlight(flightKey, async () => {
    const supabase = getSupabaseServiceRole()
    const { trades } = await paginateLeaderboardTradeRows(supabase, {
      maxRows: capped,
      operation: "leaderboard_trade_rows_server",
    })
    return trades
  })
}
