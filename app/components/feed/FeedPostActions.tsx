"use client"

import { memo, useCallback } from "react"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostActionsProps = {
  post: any
  user: any
  commentCount: number
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  onToggleLike: (post: any) => void
  onOpenComments: () => void
  onSharePost: (post: any) => void
}

function FeedPostActions({
  post,
  user,
  commentCount,
  likeMeta,
  likeBusy = false,
  onToggleLike,
  onOpenComments,
  onSharePost,
}: FeedPostActionsProps) {
  const handleOpenComments = useCallback(
    () => onOpenComments(),
    [onOpenComments]
  )

  return (
    <div className="border-t border-white/10 px-4 py-1.5">
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
    </div>
  )
}

export default memo(FeedPostActions)

const EMPTY_COMMENTS: any[] = []
