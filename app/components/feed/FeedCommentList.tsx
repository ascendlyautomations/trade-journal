"use client"

import { memo, useMemo } from "react"
import { buildCommentThreads } from "@/lib/commentThreads"
import { buildCommentUsernameMap } from "@/lib/commentReplyUx"
import CommentReplyThread from "@/app/components/comments/CommentReplyThread"
import FeedCommentItem from "./FeedCommentItem"

type FeedCommentListProps = {
  comments: any[]
  currentUserId?: string | null
  replyAvatarClassName?: string
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  deleteMenuClassName?: string
}

function FeedCommentList({
  comments,
  currentUserId,
  replyAvatarClassName,
  onReply,
  onRequestDelete,
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
              onReply={onReply}
              onRequestDelete={onRequestDelete}
              deleteMenuClassName={deleteMenuClassName}
            />
            <CommentReplyThread
              replies={replies}
              topLevelCommentCount={topLevel.length}
              mentionUserIdsByUsername={mentionUserIdsByUsername}
              currentUserId={currentUserId}
              replyAvatarClassName={replyAvatarClassName}
              onReply={onReply}
              onRequestDelete={onRequestDelete}
              deleteMenuClassName={deleteMenuClassName}
            />
          </div>
        )
      })}
    </div>
  )
}

export default memo(FeedCommentList)
