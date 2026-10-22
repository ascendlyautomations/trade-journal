import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"

const PAGE_SIZE = 1000

/** Service-role scan of public leaderboard trade rows (homepage SSR). */
export async function fetchLeaderboardTradeRowsServer(
  maxRows = 3000
): Promise<TradeForLeaderboard[]> {
  const supabase = getSupabaseServiceRole()
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
      console.error("[leaderboard] trade rows page server error:", error)
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
