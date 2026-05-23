"use client"

import { memo } from "react"
import FeedCommentItem from "./FeedCommentItem"

type FeedCommentListProps = {
  comments: any[]
}

function FeedCommentList({ comments }: FeedCommentListProps) {
  return (
    <div className="space-y-2">
      {comments.map((comment) => (
        <FeedCommentItem key={String(comment.id)} comment={comment} />
      ))}
    </div>
  )
}

export default memo(FeedCommentList)
