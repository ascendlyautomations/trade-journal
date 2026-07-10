import type { Achievement } from "./achievementTypes"
import { achievementTypeLabel } from "./achievementTypes"
import type { PayoutHistoryEntry } from "./propfirmPayoutCycles"

export type AccountHistoryEvent =
  | {
      kind: "payout"
      date: string
      payout: PayoutHistoryEntry
    }
  | {
      kind: "achievement"
      date: string
      achievement: Achievement
    }

function eventTimestamp(iso: string | null | undefined): number {
  if (!iso) return 0
  const parsed = new Date(iso).getTime()
  return Number.isNaN(parsed) ? 0 : parsed
}

export function buildAccountHistoryTimeline(
  payouts: PayoutHistoryEntry[],
  achievements: Achievement[]
): AccountHistoryEvent[] {
  const payoutEvents: AccountHistoryEvent[] = payouts.map((payout) => ({
    kind: "payout",
    date: String(payout.ended_at ?? payout.started_at ?? ""),
    payout,
  }))

  const achievementEvents: AccountHistoryEvent[] = achievements.map(
    (achievement) => ({
      kind: "achievement",
      date: String(achievement.achieved_at ?? achievement.created_at ?? ""),
      achievement,
    })
  )

  return [...payoutEvents, ...achievementEvents].sort(
    (left, right) => eventTimestamp(right.date) - eventTimestamp(left.date)
  )
}

export function accountHistoryAchievementLabel(
  achievement: Achievement
): string {
  return achievement.title?.trim() || achievementTypeLabel(achievement.achievement_type)
}

export function formatAccountHistoryDate(iso: string | null | undefined): string {
  if (!iso) return "—"
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return "—"
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}
