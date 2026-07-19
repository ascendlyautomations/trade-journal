"use client"

import { memo, useCallback, useMemo } from "react"
import AchievementCard from "@/app/components/AchievementCard"
import { achievementFromPost } from "@/lib/achievementPostEngagement"
import FeedPostActions from "./FeedPostActions"
import FeedPostHeader from "./FeedPostHeader"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedAchievementPostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  likeBusy?: boolean
  commentCount?: number
  comments?: any[]
  mediaPriority?: boolean
  commentSubmitting?: boolean
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSharePost: (post: any) => void
}

function FeedAchievementPostCard({
  post,
  user,
  likeMeta = { count: 0, liked: false },
  likeBusy = false,
  commentCount,
  comments = EMPTY_COMMENTS,
  mediaPriority = false,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSharePost,
}: FeedAchievementPostCardProps) {
  const achievement = useMemo(() => achievementFromPost(post), [post])

  const handleOpenComments = useCallback(() => {
    onOpenComments(post)
  }, [onOpenComments, post])

  const handleArticleClick = useCallback(() => {
    onSelectPost(post)
  }, [onSelectPost, post])

  const handleArticleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        onSelectPost(post)
      }
    },
    [onSelectPost, post]
  )

  const avatarUrl = useMemo(() => {
    const raw = post.profiles?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles?.avatar_url])

  const profileUsername = post.profiles?.username || "User"

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="cursor-pointer overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
    >
      <FeedPostHeader
        userId={post.user_id}
        avatarUrl={avatarUrl}
        username={profileUsername}
        metaLabel="Achievement"
        metaLabelClassName="font-medium text-amber-400/90"
        postedAt={post.created_at}
      />

      <div className="px-4 pt-3">
        <AchievementCard
          achievement={achievement}
          showVisibility={false}
          mediaPriority={mediaPriority}
        />
      </div>

      <FeedPostActions
        post={post}
        user={user}
        commentCount={commentCount ?? comments.length}
        likeMeta={likeMeta}
        likeBusy={likeBusy}
        onToggleLike={onToggleLike}
        onOpenComments={handleOpenComments}
        onSharePost={onSharePost}
      />
    </article>
  )
}

export default memo(FeedAchievementPostCard)

const EMPTY_COMMENTS: any[] = []
