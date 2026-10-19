import type { LeaderboardRankedTrader, LeaderboardView } from "./leaderboardChart.ts"
import { LEADERBOARD_PRESET_VIEW_ORDER } from "./leaderboardTimeframeFallback.ts"

export const LEADERBOARD_DEFAULT_MIN_RANKED_TRADERS = 3

export function countDistinctRankedTraders(
  rankedTraders: readonly LeaderboardRankedTrader[]
): number {
  const seen = new Set<string>()
  for (const row of rankedTraders) {
    const id = String(row.userId ?? "").trim()
    if (id) seen.add(id)
  }
  return seen.size
}

/** Pick preset from successful probes (shortest → longest). Failed probes are omitted. */
export function pickDefaultLeaderboardPresetFromProbes(
  probes: readonly { view: LeaderboardView; count: number }[]
): LeaderboardView {
  if (probes.length === 0) return LEADERBOARD_PRESET_VIEW_ORDER[0]

  for (const probe of probes) {
    if (probe.count >= LEADERBOARD_DEFAULT_MIN_RANKED_TRADERS) return probe.view
  }

  let bestView = probes[0].view
  let bestCount = probes[0].count
  for (let i = 1; i < probes.length; i += 1) {
    const probe = probes[i]
    if (probe.count > bestCount) {
      bestCount = probe.count
      bestView = probe.view
    }
  }
  return bestView
}
