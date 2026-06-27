"use client"

import { memo, useCallback, useMemo } from "react"
import AchievementCard from "@/app/components/AchievementCard"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import type { Achievement } from "@/lib/achievements"

type ProfileAchievementSocialCardProps = {
  achievement: Achievement
  achievementPostId: string
  profileUserId: string
  featured?: boolean
  showVisibility?: boolean
  currentUser: { id: string } | null
  likeMeta: { count: number; liked: boolean }
  likeBusy?: boolean
  comments: any[]
  onSelectPost: () => void
  onOpenComments: () => void
  onLike: () => void
  onSharePost?: () => void
  onImageClick?: (
    src: string,
    achievement: Achievement
  ) => void
}

function ProfileAchievementSocialCard({
  achievement,
  achievementPostId,
  profileUserId,
  featured = false,
  showVisibility = false,
  currentUser,
  likeMeta,
  likeBusy = false,
  comments,
  onSelectPost,
  onOpenComments,
  onLike,
  onSharePost,
  onImageClick,
}: ProfileAchievementSocialCardProps) {
  const postStub = useMemo(
    () => ({
      id: achievementPostId,
      feedKind: "achievement" as const,
      user_id: profileUserId,
      achievement_id: achievement.id,
      achievements: achievement,
    }),
    [achievement, achievementPostId, profileUserId]
  )

  const handleArticleClick = useCallback(() => {
    onSelectPost()
  }, [onSelectPost])

  const handleArticleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        onSelectPost()
      }
    },
    [onSelectPost]
  )

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="cursor-pointer overflow-hidden rounded-xl border border-white/10 bg-white/5 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07]"
    >
      <AchievementCard
        achievement={achievement}
        featured={featured}
        showVisibility={showVisibility}
        onImageClick={onImageClick}
      />
      <div
        className="border-t border-white/10 px-3 py-2"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <PostInteractionsEngagement
          post={postStub}
          user={currentUser}
          comments={comments}
          likeMeta={likeMeta}
          likeBusy={likeBusy}
          onToggleLike={() => onLike()}
          onOpenComments={() => onOpenComments()}
          onSharePost={onSharePost ? () => onSharePost() : undefined}
          stopPropagation
        />
      </div>
    </article>
  )
}

export default memo(ProfileAchievementSocialCard)
