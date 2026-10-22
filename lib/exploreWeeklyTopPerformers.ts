import type { LeaderboardProfileFields } from "./leaderboardAggregate.ts"
import { fetchLeaderboardPayload } from "./leaderboardFetch.ts"
import { fetchLeaderboardTradeRowsClient } from "./leaderboardTradeRowsClient.ts"
import { supabase } from "./supabaseClient.ts"
import { isDemoModeActive } from "./demo/demoMode.ts"
import {
  buildWeeklyTopPerformersPayload,
  type ExploreWeeklyTopPerformer,
  type WeeklyTopPerformersPayload,
} from "./weeklyTopPerformersBuild.ts"

export type { ExploreWeeklyTopPerformer, WeeklyTopPerformersPayload } from "./weeklyTopPerformersBuild.ts"
export type { ExploreWeeklyTopCategory } from "./exploreWeeklyTopPerformersPick.ts"
export { pickExploreWeeklyTopPerformers, pickWeeklyTopPerformersInRange } from "./exploreWeeklyTopPerformersPick.ts"

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
}): Promise<WeeklyTopPerformersPayload> {
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

  const seedProfiles = leaderboardPayload?.profiles ?? {}
  let payload = buildWeeklyTopPerformersPayload(trades, seedProfiles, nowIso)

  if (payload.performers.length === 0) {
    return payload
  }

  const profiles = await hydrateProfiles(
    payload.performers.map((p) => p.userId),
    seedProfiles
  )
  payload = buildWeeklyTopPerformersPayload(trades, profiles, nowIso)
  return payload
}

/** @deprecated Use fetchExploreWeeklyTopPerformers — returns performers only. */
export async function fetchExploreWeeklyTopPerformersLegacy(
  options: Parameters<typeof fetchExploreWeeklyTopPerformers>[0]
): Promise<ExploreWeeklyTopPerformer[]> {
  const payload = await fetchExploreWeeklyTopPerformers(options)
  return payload.performers
}
