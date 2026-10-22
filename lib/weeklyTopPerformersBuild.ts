import type { LeaderboardProfileFields } from "./leaderboardAggregate.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import {
  pickWeeklyTopPerformersInRange,
  type ExploreWeeklyTopPerformerPick,
} from "./exploreWeeklyTopPerformersPick.ts"
import {
  resolveWeeklyLeaderboardPeriod,
  weeklyLeaderboardDisplayCopy,
  type WeeklyLeaderboardPeriod,
} from "./weeklyLeaderboardPeriod.ts"
import { formatRR, formatSignedPnlDisplay } from "./formatDisplay.ts"

export type ExploreWeeklyTopPerformer = {
  category: "pnl" | "rr" | "winRate"
  userId: string
  username: string | null
  name: string | null
  avatar_url: string | null
  metricLabel: string
  metricDisplay: string
}

export type WeeklyTopPerformersPayload = {
  performers: ExploreWeeklyTopPerformer[]
  periodTitle: string
  periodSubtitle: string
  isHistoricalPeriod: boolean
  period: WeeklyLeaderboardPeriod | null
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

export function buildWeeklyTopPerformersPayload(
  trades: TradeForLeaderboard[],
  profiles: Record<string, LeaderboardProfileFields>,
  nowIso?: string
): WeeklyTopPerformersPayload {
  const now = nowIso ? new Date(nowIso) : new Date()
  const period = resolveWeeklyLeaderboardPeriod(trades, now)

  if (!period) {
    return {
      performers: [],
      periodTitle: "Top Performers This Week",
      periodSubtitle:
        "Calendar week rankings from public trades (all accounts)",
      isHistoricalPeriod: false,
      period: null,
    }
  }

  const copy = weeklyLeaderboardDisplayCopy(period)
  const picks = pickWeeklyTopPerformersInRange(trades, period.start, period.end)

  const performers = picks.map((pick) => {
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

  return {
    performers,
    periodTitle: copy.title,
    periodSubtitle: copy.subtitle,
    isHistoricalPeriod: copy.isHistoricalPeriod,
    period,
  }
}
