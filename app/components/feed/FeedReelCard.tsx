"use client"

import { memo, useCallback, useMemo } from "react"
import FeedReelCardActions from "./FeedReelCardActions"
import ReelThumbnailPreview from "@/app/components/ReelThumbnailPreview"
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
  onOpenLinkedTrade?: (post: any) => void
  onToggleLike: (post: any) => void
  onSharePost: (post: any) => void
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
  onOpenLinkedTrade,
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

  const handleOpenLinkedTrade = useCallback(() => {
    onOpenLinkedTrade?.(post)
  }, [onOpenLinkedTrade, post])

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
        <ReelThumbnailPreview reel={post} onClick={handleArticleClick} />
        {caption ? (
          <p className="mt-3 line-clamp-3 whitespace-pre-wrap text-sm text-gray-200">
            {caption}
          </p>
        ) : null}
      </div>

      <FeedReelCardActions
        post={post}
        user={user}
        comments={comments}
        likeMeta={likeMeta}
        likeBusy={likeBusy}
        showLinkedTradeBadge={tradeAttached}
        onToggleLike={onToggleLike}
        onOpenComments={handleOpenComments}
        onSharePost={onSharePost}
        onOpenLinkedTrade={onOpenLinkedTrade ? handleOpenLinkedTrade : undefined}
      />
    </article>
  )
}

export default memo(FeedReelCard)
