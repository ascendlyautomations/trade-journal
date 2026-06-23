"use client"

import { memo, useMemo } from "react"
import {
  indexCommentsById,
  resolveParentComment,
} from "@/lib/replyReference"
import FeedCommentItem from "./FeedCommentItem"

type FeedCommentListProps = {
  comments: any[]
  currentUserId?: string | null
  onReply?: (comment: any) => void
  onReplyUnavailable?: () => void
  onRequestDelete?: (comment: any) => void
  deleteMenuClassName?: string
}

function FeedCommentList({
  comments,
  currentUserId,
  onReply,
  onReplyUnavailable,
  onRequestDelete,
  deleteMenuClassName,
}: FeedCommentListProps) {
  const commentsById = useMemo(() => indexCommentsById(comments), [comments])

  return (
    <div className="space-y-2">
      {comments.map((comment) => (
        <FeedCommentItem
          key={String(comment.id)}
          comment={comment}
          parentComment={resolveParentComment(comment, commentsById)}
          currentUserId={currentUserId}
          onReply={onReply}
          onReplyUnavailable={onReplyUnavailable}
          onRequestDelete={onRequestDelete}
          deleteMenuClassName={deleteMenuClassName}
        />
      ))}
    </div>
  )
}

export default memo(FeedCommentList)
