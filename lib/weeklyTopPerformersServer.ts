import type { LeaderboardProfileFields } from "./leaderboardAggregate.ts"
import { fetchLeaderboardTradeRowsServer } from "./leaderboardTradeRowsServer.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"
import {
  buildWeeklyTopPerformersPayload,
  type WeeklyTopPerformersPayload,
} from "./weeklyTopPerformersBuild.ts"
import { serviceRoleTableRead } from "./supabaseServiceTableRead.ts"

async function hydrateProfilesForUserIds(
  userIds: string[],
  seed: Record<string, LeaderboardProfileFields>
): Promise<Record<string, LeaderboardProfileFields>> {
  const profiles = { ...seed }
  const missing = userIds.filter((id) => !profiles[id])
  if (missing.length === 0) return profiles

  let rows: { id: string; username: string | null; name: string | null; avatar_url: string | null }[] =
    []
  const db = getSupabaseServiceRole()
  try {
    rows = await serviceRoleTableRead(
      db,
      "weekly_top_performers_profile_hydrate",
      async (signal) => {
        const result = await db
          .from("profiles")
          .select("id, username, name, avatar_url")
          .in("id", missing)
          .abortSignal(signal)
        return { data: result.data, error: result.error }
      }
    )
  } catch (error) {
    console.error("[weekly-top-performers] profile hydrate:", error)
    return profiles
  }

  for (const row of rows ?? []) {
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
