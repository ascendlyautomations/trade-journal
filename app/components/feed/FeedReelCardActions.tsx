"use client"

import { memo, useCallback } from "react"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import LinkedTradeBadge from "./LinkedTradeBadge"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedReelCardActionsProps = {
  post: any
  user: any
  commentCount: number
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  showLinkedTradeBadge?: boolean
  onToggleLike: (post: any) => void
  onOpenComments: () => void
  onSharePost: (post: any) => void
  onOpenLinkedTrade?: () => void
}

function FeedReelCardActions({
  post,
  user,
  commentCount,
  likeMeta,
  likeBusy = false,
  showLinkedTradeBadge = false,
  onToggleLike,
  onOpenComments,
  onSharePost,
  onOpenLinkedTrade,
}: FeedReelCardActionsProps) {
  const handleOpenComments = useCallback(
    () => onOpenComments(),
    [onOpenComments]
  )

  return (
    <div className="border-t border-white/10 px-4 py-2">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <PostInteractionsEngagement
            post={post}
            user={user}
          comments={EMPTY_COMMENTS}
          commentCount={commentCount}
            likeMeta={likeMeta}
            likeBusy={likeBusy}
            onToggleLike={onToggleLike}
            onOpenComments={handleOpenComments}
            onSharePost={onSharePost}
            stopPropagation
          />
        </div>
        {showLinkedTradeBadge && onOpenLinkedTrade ? (
          <LinkedTradeBadge
            onClick={(e) => {
              e.stopPropagation()
              onOpenLinkedTrade()
            }}
          />
        ) : null}
      </div>
    </div>
  )
}

export default memo(FeedReelCardActions)

const EMPTY_COMMENTS: any[] = []
