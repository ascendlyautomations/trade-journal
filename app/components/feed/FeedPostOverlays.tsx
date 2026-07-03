"use client"

import { memo, type MutableRefObject } from "react"
import FeedPostDetailModal from "./FeedPostDetailModal"
import FeedProfilePostDetailModal from "./FeedProfilePostDetailModal"
import FeedReelDetailModal from "./FeedReelDetailModal"
import ShareToConversationsModal from "@/app/components/ShareToConversationsModal"
import type { FeedLikeMeta } from "./FeedPostCard"
import { isTradeAttachedReel } from "@/lib/reels"

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
  openTradeRef?: MutableRefObject<Record<string, boolean>>
  tradeExpandSignal?: number
  onCloseDetailModal: () => void
  onCloseShareOverlay: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onSharePost: (post: any) => void
  openReelMenuId?: string | null
  onReelMenuToggle?: (reelId: string) => void
  onEditReel?: (post: any) => void
  onDeleteReel?: (post: any) => void
  onReplaceReelVideo?: (post: any) => void
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
  openTradeRef,
  tradeExpandSignal = 0,
  onCloseDetailModal,
  onCloseShareOverlay,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
  onSharePost,
  openReelMenuId = null,
  onReelMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
}: FeedPostOverlaysProps) {
  return (
    <>
      {selectedPost && selectedPostId ? (
        selectedPost.feedKind === "reel" ? (
          <FeedReelDetailModal
            key={selectedPostId}
            post={selectedPost}
            user={user}
            comments={selectedPostComments}
            likeMeta={selectedPostLikeMeta}
            likeBusy={selectedPostLikeBusy}
            commentSubmitting={selectedPostCommentSubmitting}
            draftSyncRef={draftSyncRef}
            openCommentsRef={openCommentsRef}
            openTradeRef={openTradeRef}
            tradeExpandSignal={tradeExpandSignal}
            onClose={onCloseDetailModal}
            onToggleLike={onToggleLike}
            onSubmitComment={onSubmitComment}
            onDeleteComment={onDeleteComment}
            onSharePost={onSharePost}
            canManageReel={
              user?.id != null &&
              String(user.id) === String(selectedPost.user_id)
            }
            menuOpen={openReelMenuId === selectedPostId}
            onMenuToggle={() => onReelMenuToggle?.(selectedPostId)}
            onEditReel={() => onEditReel?.(selectedPost)}
            onDeleteReel={() => onDeleteReel?.(selectedPost)}
            onReplaceReelVideo={() => onReplaceReelVideo?.(selectedPost)}
            isTradeAttachedReel={isTradeAttachedReel(selectedPost)}
          />
        ) : selectedPost.feedKind === "profile" ||
        selectedPost.feedKind === "achievement" ? (
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
            onDeleteComment={onDeleteComment}
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
            onDeleteComment={onDeleteComment}
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
          feedKind={
            sharePost.feedKind === "profile"
              ? "profile"
              : sharePost.feedKind === "achievement"
                ? "achievement"
                : sharePost.feedKind === "reel"
                  ? "reel"
                  : "trade"
          }
          post={sharePost}
          captionPlaceholder="Add a message..."
          showCancel={false}
        />
      ) : null}
    </>
  )
}

export default memo(FeedPostOverlays)
