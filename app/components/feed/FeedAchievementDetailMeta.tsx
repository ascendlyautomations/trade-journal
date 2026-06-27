"use client"

import type { Achievement } from "@/lib/achievements"
import {
  achievementTypeLabel,
  categoryFromType,
  formatAchievementDate,
} from "@/lib/achievements"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"

function formatCategoryLabel(achievement: Achievement): string {
  const raw = achievement.category ?? categoryFromType(achievement.achievement_type)
  if (raw === "payouts") return "Payouts"
  if (raw === "passed_evals") return "Passed Evals"
  if (raw === "milestones") return "Milestones"
  return String(raw)
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ")
}

type FeedAchievementDetailMetaProps = {
  achievement: Achievement
  /** Social post timestamp (e.g. when the achievement post was created). */
  postedAt?: string | null
}

export default function FeedAchievementDetailMeta({
  achievement,
  postedAt,
}: FeedAchievementDetailMetaProps) {
  const unlockDate = formatAchievementDate(achievement.achieved_at)
  const relativeTime = formatSocialTimestamp(
    postedAt ?? achievement.created_at ?? achievement.achieved_at
  )
  const description =
    achievement.description != null && achievement.description.trim() !== ""
      ? achievement.description.trim()
      : null

  return (
    <div className="space-y-2 border-b border-white/10 px-4 py-3 text-sm">
      <h3 className="text-base font-semibold leading-snug text-white">
        {achievement.title}
      </h3>
      <p className="text-xs uppercase tracking-wide text-blue-200/80">
        {formatCategoryLabel(achievement) || achievementTypeLabel(achievement.achievement_type)}
      </p>
      {description ? (
        <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-300">
          {description}
        </p>
      ) : null}
      <div className="space-y-0.5 pt-0.5 text-xs text-white/50">
        <p>Unlocked {unlockDate}</p>
        <p>{relativeTime}</p>
      </div>
    </div>
  )
}
