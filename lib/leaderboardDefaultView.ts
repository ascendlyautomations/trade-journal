import type { LeaderboardView } from "./leaderboardChart.ts"
import { fetchLeaderboardPayload } from "./leaderboardFetch.ts"
import {
  leaderboardAggregateCacheKey,
  normalizeLeaderboardPayload,
  type LeaderboardPayload,
  type LeaderboardQuery,
} from "./leaderboardAggregate.ts"
import { readLeaderboardAggregate, writeLeaderboardAggregate } from "./leaderboardSessionCache.ts"
import { LEADERBOARD_PRESET_VIEW_ORDER } from "./leaderboardTimeframeFallback.ts"
import {
  countDistinctRankedTraders,
  LEADERBOARD_DEFAULT_MIN_RANKED_TRADERS,
  pickDefaultLeaderboardPresetFromProbes,
} from "./leaderboardDefaultViewSelection.ts"

export {
  countDistinctRankedTraders,
  LEADERBOARD_DEFAULT_MIN_RANKED_TRADERS,
  pickDefaultLeaderboardPresetFromProbes,
} from "./leaderboardDefaultViewSelection.ts"

/**
 * Probe presets smallest → largest using session aggregate cache, then network.
 * Stops early once a window has enough distinct ranked traders.
 */
export async function resolveInitialLeaderboardPresetView(
  queryBase: Omit<LeaderboardQuery, "view">
): Promise<{ view: LeaderboardView; payload: LeaderboardPayload | null }> {
  const probes: { view: LeaderboardView; count: number; payload: LeaderboardPayload }[] =
    []

  for (const presetView of LEADERBOARD_PRESET_VIEW_ORDER) {
    const query: LeaderboardQuery = { ...queryBase, view: presetView }
    const queryKey = leaderboardAggregateCacheKey(query)

    let payload = normalizeLeaderboardPayload(readLeaderboardAggregate(queryKey))
    if (!payload) {
      try {
        payload = await fetchLeaderboardPayload(query)
        writeLeaderboardAggregate(queryKey, payload)
      } catch (error) {
        console.error(
          `[leaderboard] default timeframe probe failed (${presetView}):`,
          error
        )
        continue
      }
    }

    const count = countDistinctRankedTraders(payload.rankedTraders)
    probes.push({ view: presetView, count, payload })

    if (count >= LEADERBOARD_DEFAULT_MIN_RANKED_TRADERS) {
      return { view: presetView, payload }
    }
  }

  const view = pickDefaultLeaderboardPresetFromProbes(probes)
  const match = probes.find((probe) => probe.view === view)
  return { view, payload: match?.payload ?? null }
}
