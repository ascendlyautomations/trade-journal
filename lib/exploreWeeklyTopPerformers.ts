import type { LeaderboardProfileFields } from "./leaderboardAggregate.ts"
import { fetchLeaderboardPayload } from "./leaderboardFetch.ts"
import { fetchLeaderboardTradeRowsClient } from "./leaderboardTradeRowsClient.ts"
import { supabase } from "./supabaseClient.ts"
import { isDemoModeActive } from "./demo/demoMode.ts"
import { formatRR, formatSignedPnlDisplay } from "./formatDisplay.ts"
import {
  pickExploreWeeklyTopPerformers,
  type ExploreWeeklyTopCategory,
  type ExploreWeeklyTopPerformerPick,
} from "./exploreWeeklyTopPerformersPick.ts"

export type { ExploreWeeklyTopCategory } from "./exploreWeeklyTopPerformersPick.ts"
export { pickExploreWeeklyTopPerformers } from "./exploreWeeklyTopPerformersPick.ts"

export type ExploreWeeklyTopPerformer = {
  category: ExploreWeeklyTopCategory
  userId: string
  username: string | null
  name: string | null
  avatar_url: string | null
  metricLabel: string
  metricDisplay: string
}

function formatWeeklyMetricDisplay(pick: ExploreWeeklyTopPerformerPick): string {
  if (pick.category === "pnl") {
    return formatSignedPnlDisplay(pick.totalPnl ?? 0)
  }
  if (pick.category === "rr") {
    return pick.avgRR != null ? formatRR(pick.avgRR) : "—"
  }
  return pick.winRatePct != null ? `${pick.winRatePct.toFixed(1)}%` : "—"
}

async function hydrateProfiles(
  userIds: string[],
  seed: Record<string, LeaderboardProfileFields>
): Promise<Record<string, LeaderboardProfileFields>> {
  const profiles = { ...seed }
  const missing = userIds.filter((id) => !profiles[id])
  if (missing.length === 0 || isDemoModeActive()) return profiles

  const { data, error } = await supabase
    .from("profiles")
    .select("id, username, name, avatar_url")
    .in("id", missing)

  if (error) {
    console.error("[explore] weekly top performer profiles:", error)
    return profiles
  }

  for (const row of data ?? []) {
    profiles[String(row.id)] = row as LeaderboardProfileFields
  }
  return profiles
}

export async function fetchExploreWeeklyTopPerformers(options: {
  viewerId: string | null
  nowIso?: string
}): Promise<ExploreWeeklyTopPerformer[]> {
  const nowIso = options.nowIso ?? new Date().toISOString()

  const [trades, leaderboardPayload] = await Promise.all([
    fetchLeaderboardTradeRowsClient(),
    fetchLeaderboardPayload({
      view: "7D",
      accountType: "all",
      nowIso,
      viewerId: options.viewerId,
    }).catch((error) => {
      console.error("[explore] weekly top leaderboard payload:", error)
      return null
    }),
  ])

  const picks = pickExploreWeeklyTopPerformers(trades, new Date(nowIso))
  if (picks.length === 0) return []

  const profiles = await hydrateProfiles(
    picks.map((p) => p.userId),
    leaderboardPayload?.profiles ?? {}
  )

  return picks.map((pick) => {
    const profile = profiles[pick.userId]
    return {
      category: pick.category,
      userId: pick.userId,
      metricLabel: pick.metricLabel,
      metricDisplay: formatWeeklyMetricDisplay(pick),
      username: profile?.username ?? null,
      name: profile?.name ?? null,
      avatar_url: profile?.avatar_url ?? null,
    }
  })
}
