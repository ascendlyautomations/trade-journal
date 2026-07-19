"use client"

import type { ComponentProps } from "react"
import AchievementCard from "@/app/components/AchievementCard"
import ProfileAchievementSocialCard from "@/app/components/ProfileAchievementSocialCard"
import type { FeedLikeMeta } from "@/app/components/feed/FeedPostCard"
import type { Achievement } from "@/lib/achievements"

type SocialCardComments = ComponentProps<
  typeof ProfileAchievementSocialCard
>["comments"]

const EMPTY_LIKE_META = { count: 0, liked: false } as const

type ProfileAchievementsTabProps = {
  ready: boolean
  achievements: Achievement[]
  profileUserId: string
  currentUserId: string | null
  achievementPostIds: Record<string, string>
  likesByPost: Record<string, FeedLikeMeta>
  likeBusyByPost: Record<string, boolean>
  commentsByPost: Record<string, SocialCardComments>
  onOpenDetail: (achievement: Achievement) => void
  onLike: (postId: string) => void
  onOpenPost: (
    achievement: Achievement,
    postId: string,
    focusComments: boolean
  ) => void
  onShare: (achievement: Achievement, postId: string) => void
}

export default function ProfileAchievementsTab({
  ready,
  achievements,
  profileUserId,
  currentUserId,
  achievementPostIds,
  likesByPost,
  likeBusyByPost,
  commentsByPost,
  onOpenDetail,
  onLike,
  onOpenPost,
  onShare,
}: ProfileAchievementsTabProps) {
  const renderAchievement = (
    achievement: Achievement,
    featured: boolean
  ) => {
    const postId = achievementPostIds[String(achievement.id)]
    if (!postId) {
      return (
        <AchievementCard
          key={achievement.id}
          achievement={achievement}
          featured={featured || undefined}
          showVisibility={featured ? false : undefined}
          onOpenDetail={onOpenDetail}
        />
      )
    }

    return (
      <ProfileAchievementSocialCard
        key={achievement.id}
        achievement={achievement}
        achievementPostId={postId}
        profileUserId={profileUserId}
        featured={featured || undefined}
        showVisibility={featured ? false : undefined}
        currentUser={currentUserId ? { id: currentUserId } : null}
        likeMeta={likesByPost[postId] || EMPTY_LIKE_META}
        likeBusy={!!likeBusyByPost[postId]}
        comments={commentsByPost[postId] || []}
        onLike={() => onLike(postId)}
        onSelectPost={() => onOpenPost(achievement, postId, false)}
        onOpenComments={() => onOpenPost(achievement, postId, true)}
        onSharePost={
          currentUserId ? () => onShare(achievement, postId) : undefined
        }
      />
    )
  }

  return (
    <div className="space-y-4">
      {!ready ? (
        <div className="grid gap-3 sm:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-40 animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : achievements.length === 0 ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center">
          <p className="text-sm text-gray-300">
            {currentUserId === profileUserId
              ? "No achievements yet."
              : "No public achievements yet."}
          </p>
        </div>
      ) : (
        <>
          {achievements.some((achievement) => achievement.is_featured) ? (
            <div className="space-y-2">
              <h3 className="text-sm font-semibold text-white">Featured</h3>
              <div className="grid gap-3 sm:grid-cols-2">
                {achievements
                  .filter((achievement) => achievement.is_featured)
                  .map((achievement) => renderAchievement(achievement, true))}
              </div>
            </div>
          ) : null}
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {achievements
              .filter((achievement) => !achievement.is_featured)
              .map((achievement) => renderAchievement(achievement, false))}
          </div>
        </>
      )}
    </div>
  )
}
