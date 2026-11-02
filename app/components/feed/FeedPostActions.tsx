"use client"

import { memo, useCallback } from "react"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import { vaultRefFromFeedItem } from "@/lib/vault/refs"
import type { FeedLikeMeta } from "./FeedPostCard"
import { FEED_CARD_ENGAGEMENT_ROW_CLASS } from "@/app/components/ui/detailModalEngagement"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

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
  const phoneWeb = !useIsNativeIos()
  const handleOpenComments = useCallback(
    () => onOpenComments(),
    [onOpenComments]
  )

  return (
    <div
      className={`${FEED_CARD_ENGAGEMENT_ROW_CLASS}${
        phoneWeb ? " max-md:px-3" : ""
      }`}
    >
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
          vaultContentRef={vaultRefFromFeedItem(post)}
          stopPropagation
        />
      </div>
    </div>
  )
}

export default memo(FeedPostActions)

const EMPTY_COMMENTS: any[] = []
