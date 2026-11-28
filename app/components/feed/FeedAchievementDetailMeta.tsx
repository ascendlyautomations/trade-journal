"use client"

import type { Achievement } from "@/lib/achievements"
import { formatAchievementDate } from "@/lib/achievements"
import AchievementPublicContentStack from "@/app/components/achievement/AchievementPublicContentStack"

type FeedAchievementDetailMetaProps = {
  achievement: Achievement
  showPrivacy?: boolean
}

export default function FeedAchievementDetailMeta({
  achievement,
  showPrivacy = true,
}: FeedAchievementDetailMetaProps) {
  const unlockDate = formatAchievementDate(achievement.achieved_at)

  return (
    <div className="space-y-1 border-b border-white/10 px-4 py-1 text-sm">
      <AchievementPublicContentStack achievement={achievement} />
      <div className="space-y-0.5 pt-0.5 text-xs text-gray-400">
        <p>Unlocked {unlockDate}</p>
        {showPrivacy ? (
          <p>{achievement.is_public ? "Public" : "Private"}</p>
        ) : null}
      </div>
    </div>
  )
}