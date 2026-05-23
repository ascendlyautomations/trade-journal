"use client"

import { memo } from "react"

type FeedCommentItemProps = {
  comment: any
}

function FeedCommentItem({ comment }: FeedCommentItemProps) {
  return (
    <div className="flex gap-2 items-start">
      <img
        src={comment.profiles?.avatar_url || "/default-avatar.png"}
        className="w-8 h-8 rounded-full object-cover shrink-0"
        alt="avatar"
        loading="lazy"
        decoding="async"
      />
      <div className="min-w-0">
        <p className="text-xs text-gray-400">
          {comment.profiles?.username || "User"}
        </p>
        <p className="text-white text-sm break-words">{comment.content}</p>
      </div>
    </div>
  )
}

export default memo(FeedCommentItem)
