"use client"

import { memo } from "react"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostActionsProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: FeedLikeMeta
  commentsOpen: boolean
  onToggleLike: (post: any) => void
  onToggleComments: () => void
  onSharePost: (post: any) => void
}

function FeedPostActions({
  post,
  user,
  comments,
  likeMeta,
  commentsOpen,
  onToggleLike,
  onToggleComments,
  onSharePost,
}: FeedPostActionsProps) {
  return (
    <div className="border-t border-white/10 px-4 py-2">
      <div className="min-w-0">
        <PostInteractionsEngagement
          post={post}
          user={user}
          comments={comments}
          likeMeta={likeMeta}
          commentsOpen={commentsOpen}
          onToggleLike={onToggleLike}
          onToggleComments={(_postId) => onToggleComments()}
          onSharePost={onSharePost}
          stopPropagation
        />
      </div>
    </div>
  )
}

export default memo(FeedPostActions)
