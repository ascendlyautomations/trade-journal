"use client"

import { memo, type MutableRefObject } from "react"
import FeedPostDetailModal from "./FeedPostDetailModal"
import FeedProfilePostDetailModal from "./FeedProfilePostDetailModal"
import ShareToConversationsModal from "@/app/components/ShareToConversationsModal"
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
        selectedPost.feedKind === "profile" ? (
          <FeedProfilePostDetailModal
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
        ) : (
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
        )
      ) : null}

      {sharePost ? (
        <ShareToConversationsModal
          key={sharePostId ?? undefined}
          open
          onClose={onCloseShareOverlay}
          title="Send Post"
          postId={String(sharePost.id)}
          post={sharePost}
          captionPlaceholder="Add a message..."
          showCancel={false}
        />
      ) : null}
    </>
  )
}

export default memo(FeedPostOverlays)
