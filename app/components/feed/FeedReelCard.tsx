"use client"

import { memo, useCallback, useMemo } from "react"
import FeedPostActions from "./FeedPostActions"
import FeedPostHeader from "./FeedPostHeader"
import FeedReelOwnerMenu from "./FeedReelOwnerMenu"
import type { FeedLikeMeta } from "./FeedPostCard"
import { resolveReelCaption, isTradeAttachedReel } from "@/lib/reels"

type FeedReelCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  likeBusy?: boolean
  comments?: any[]
  commentSubmitting: boolean
  canManageReel?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onEditReel?: () => void
  onDeleteReel?: () => void
  onReplaceReelVideo?: () => void
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSharePost: (post: any) => void
}

function formatReelDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds))
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${String(secs).padStart(2, "0")}`
}

function FeedReelCard({
  post,
  user,
  likeMeta = { count: 0, liked: false },
  likeBusy = false,
  comments = [],
  commentSubmitting: _commentSubmitting,
  canManageReel = false,
  menuOpen = false,
  onMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSharePost,
}: FeedReelCardProps) {
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
  const caption = useMemo(() => resolveReelCaption(post), [post])
  const tradeAttached = isTradeAttachedReel(post)

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="cursor-pointer overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
    >
      <div className="flex items-center border-b border-white/5">
        <div className="min-w-0 flex-1">
          <FeedPostHeader
            userId={post.user_id}
            avatarUrl={avatarUrl}
            username={profileUsername}
            metaLabel="Reel"
            metaLabelClassName="font-medium text-violet-400/90"
            postedAt={post.created_at}
          />
        </div>
        {canManageReel ? (
          <div className="pr-3">
            <FeedReelOwnerMenu
              menuOpen={menuOpen}
              onMenuToggle={() => onMenuToggle?.()}
              onEdit={() => onEditReel?.()}
              onDelete={() => onDeleteReel?.()}
              onReplaceVideo={() => onReplaceReelVideo?.()}
              isTradeAttached={tradeAttached}
            />
          </div>
        ) : null}
      </div>

      <div className="px-4 pt-3">
        <div className="relative mx-auto max-w-[280px] overflow-hidden rounded-xl border border-white/10 bg-black/40">
          <img
            src={String(post.thumbnail_url)}
            alt=""
            loading="lazy"
            className="aspect-[9/16] w-full object-cover"
          />
          <div className="absolute inset-0 flex items-center justify-center bg-black/20">
            <span className="flex h-12 w-12 items-center justify-center rounded-full border border-white/20 bg-black/50 text-lg text-white backdrop-blur-sm">
              ▶
            </span>
          </div>
          {post.duration_seconds != null ? (
            <span className="absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-white">
              {formatReelDuration(Number(post.duration_seconds))}
            </span>
          ) : null}
        </div>
        {caption ? (
          <p className="mt-3 line-clamp-3 whitespace-pre-wrap text-sm text-gray-200">
            {caption}
          </p>
        ) : null}
      </div>

      <FeedPostActions
        post={post}
        user={user}
        comments={comments}
        likeMeta={likeMeta}
        likeBusy={likeBusy}
        onToggleLike={onToggleLike}
        onOpenComments={handleOpenComments}
        onSharePost={onSharePost}
      />
    </article>
  )
}

export default memo(FeedReelCard)
