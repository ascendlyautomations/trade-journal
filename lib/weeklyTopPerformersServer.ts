import type { LeaderboardProfileFields } from "./leaderboardAggregate.ts"
import { fetchLeaderboardTradeRowsServer } from "./leaderboardTradeRowsServer.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"
import {
  buildWeeklyTopPerformersPayload,
  type WeeklyTopPerformersPayload,
} from "./weeklyTopPerformersBuild.ts"

async function hydrateProfilesForUserIds(
  userIds: string[],
  seed: Record<string, LeaderboardProfileFields>
): Promise<Record<string, LeaderboardProfileFields>> {
  const profiles = { ...seed }
  const missing = userIds.filter((id) => !profiles[id])
  if (missing.length === 0) return profiles

  const { data, error } = await getSupabaseServiceRole()
    .from("profiles")
    .select("id, username, name, avatar_url")
    .in("id", missing)

  if (error) {
    console.error("[weekly-top-performers] profile hydrate:", error)
    return profiles
  }

  for (const row of data ?? []) {
    profiles[String(row.id)] = row as LeaderboardProfileFields
  }
  return profiles
}

export async function fetchWeeklyTopPerformersServer(options?: {
  nowIso?: string
}): Promise<WeeklyTopPerformersPayload> {
  const nowIso = options?.nowIso ?? new Date().toISOString()

  const trades = await fetchLeaderboardTradeRowsServer()

  let payload = buildWeeklyTopPerformersPayload(trades, {}, nowIso)

  if (payload.performers.length === 0) {
    return payload
  }

  const profiles = await hydrateProfilesForUserIds(
    payload.performers.map((p) => p.userId),
    {}
  )

  return buildWeeklyTopPerformersPayload(trades, profiles, nowIso)
}
