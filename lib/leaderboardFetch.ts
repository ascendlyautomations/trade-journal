import type { TradeForLeaderboard } from "./leaderboardChart"

/**
 * All trades from users with public profiles (profiles.is_private = false).
 * Trade visibility (is_public) does not affect inclusion.
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
