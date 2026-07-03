import type { TradeForLeaderboard } from "./leaderboardChart"

/**
 * Public trades from users with public profiles (is_public + !is_private).
 * Fetched server-side — returns aggregation fields only, not trade details.
 */
export async function fetchLeaderboardTrades(): Promise<TradeForLeaderboard[]> {
  const res = await fetch("/api/leaderboard/trades", { cache: "no-store" })

  if (!res.ok) {
    console.error("[leaderboard] trade fetch error:", res.status, res.statusText)
    return []
  }

  return (await res.json()) as TradeForLeaderboard[]
}
