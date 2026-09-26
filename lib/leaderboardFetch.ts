import {
  leaderboardCustomInstants,
  normalizeLeaderboardPayload,
  type LeaderboardPayload,
  type LeaderboardQuery,
} from "./leaderboardAggregate.ts"

/**
 * Ranked leaderboard window for the current filters.
 * The response does not include raw trades.
 */
export async function fetchLeaderboardPayload(
  query: LeaderboardQuery
): Promise<LeaderboardPayload> {
  const params = new URLSearchParams({
    view: query.view,
    account: query.accountType,
    now: query.nowIso,
  })
  if (query.viewerId) params.set("viewer", query.viewerId)
  if (query.view === "Custom") {
    const bounds = leaderboardCustomInstants(
      query.customStartYmd ?? "",
      query.customEndYmd ?? ""
    )
    if (query.customStartYmd) params.set("customStart", query.customStartYmd)
    if (query.customEndYmd) params.set("customEnd", query.customEndYmd)
    if (bounds) {
      params.set("customStartAt", bounds.startIso)
      params.set("customEndAt", bounds.endIso)
    }
  }

  const res = await fetch(`/api/leaderboard/trades?${params.toString()}`, {
    cache: "no-store",
  })

  if (!res.ok) {
    console.error("[leaderboard] fetch error:", res.status, res.statusText)
    throw new Error("Couldn't load leaderboard data. Please try again.")
  }

  const payload = normalizeLeaderboardPayload(await res.json())
  if (!payload) {
    throw new Error("Couldn't load leaderboard data. Please try again.")
  }
  return payload
}
