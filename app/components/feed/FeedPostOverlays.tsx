"use client"

import { memo, type MutableRefObject } from "react"
import FeedPostDetailModal from "./FeedPostDetailModal"
import FeedSharePostOverlay from "./FeedSharePostOverlay"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostOverlaysProps = {
  selectedPostId: string | null
  selectedPost: any | null
  sharePostId: string | null
  sharePost: any | null
  user: any
  selectedPostComments: any[]
  selectedPostLikeMeta: FeedLikeMeta
  selectedPostLikeBusy?: boolean
  selectedPostCommentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onCloseDetailModal: () => void
  onCloseShareOverlay: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostOverlays({
  selectedPostId,
  selectedPost,
  sharePostId,
  sharePost,
  user,
  selectedPostComments,
  selectedPostLikeMeta,
  selectedPostLikeBusy = false,
  selectedPostCommentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onCloseDetailModal,
  onCloseShareOverlay,
  onToggleLike,
  onSubmitComment,
  onSharePost,
}: FeedPostOverlaysProps) {
  return (
    <>
      {selectedPost && selectedPostId ? (
        <FeedPostDetailModal
          key={selectedPostId}
          post={selectedPost}
          user={user}
          comments={selectedPostComments}
          likeMeta={selectedPostLikeMeta}
          likeBusy={selectedPostLikeBusy}
          commentSubmitting={selectedPostCommentSubmitting}
          draftSyncRef={draftSyncRef}
          openCommentsRef={openCommentsRef}
          onClose={onCloseDetailModal}
          onToggleLike={onToggleLike}
          onSubmitComment={onSubmitComment}
          onSharePost={onSharePost}
        />
      ) : null}

      {sharePost ? (
        <FeedSharePostOverlay
          key={sharePostId ?? undefined}
          post={sharePost}
          user={user}
          onClose={onCloseShareOverlay}
        />
      ) : null}
    </>
  )
}

export default memo(FeedPostOverlays)
