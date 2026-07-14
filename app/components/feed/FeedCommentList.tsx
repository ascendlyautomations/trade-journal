"use client"

import { memo, useMemo } from "react"
import { buildCommentThreads } from "@/lib/commentThreads"
import { buildCommentUsernameMap } from "@/lib/commentReplyUx"
import CommentReplyThread from "@/app/components/comments/CommentReplyThread"
import FeedCommentItem from "./FeedCommentItem"
import type { CommentLikeMeta } from "@/lib/commentLikes"

type FeedCommentListProps = {
  comments: any[]
  currentUserId?: string | null
  contentOwnerUserId?: string | null
  replyAvatarClassName?: string
  likesByCommentId?: Record<string, CommentLikeMeta>
  onToggleCommentLike?: (comment: any) => void
  isCommentLikeBusy?: (commentId: string) => boolean
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  onTogglePin?: (comment: any, pinned: boolean) => void
  deleteMenuClassName?: string
}

function FeedCommentList({
  comments,
  currentUserId,
  contentOwnerUserId,
  replyAvatarClassName,
  likesByCommentId,
  onToggleCommentLike,
  isCommentLikeBusy,
  onReply,
  onRequestDelete,
  onTogglePin,
  deleteMenuClassName,
}: FeedCommentListProps) {
  const { topLevel, repliesByRootId } = useMemo(
    () => buildCommentThreads(comments),
    [comments]
  )
  const mentionUserIdsByUsername = useMemo(
    () => buildCommentUsernameMap(comments),
    [comments]
  )

  return (
    <div className="space-y-2">
      {topLevel.map((comment) => {
        const rootId = String(comment.id)
        const replies = repliesByRootId.get(rootId) ?? []

        return (
          <div key={rootId}>
            <FeedCommentItem
              comment={comment}
              mentionUserIdsByUsername={mentionUserIdsByUsername}
              currentUserId={currentUserId}
              contentOwnerUserId={contentOwnerUserId}
              likeMeta={likesByCommentId?.[rootId]}
              onToggleLike={onToggleCommentLike}
              likeDisabled={isCommentLikeBusy?.(rootId) ?? false}
              onReply={onReply}
              onRequestDelete={onRequestDelete}
              onTogglePin={onTogglePin}
              deleteMenuClassName={deleteMenuClassName}
            />
            <CommentReplyThread
              replies={replies}
              topLevelCommentCount={topLevel.length}
              mentionUserIdsByUsername={mentionUserIdsByUsername}
              currentUserId={currentUserId}
              contentOwnerUserId={contentOwnerUserId}
              replyAvatarClassName={replyAvatarClassName}
              likesByCommentId={likesByCommentId}
              onToggleCommentLike={onToggleCommentLike}
              isCommentLikeBusy={isCommentLikeBusy}
              onReply={onReply}
              onRequestDelete={onRequestDelete}
              onTogglePin={onTogglePin}
              deleteMenuClassName={deleteMenuClassName}
            />
          </div>
        )
      })}
    </div>
  )
}

export default memo(FeedCommentList)
