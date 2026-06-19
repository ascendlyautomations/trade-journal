"use client"

import { memo } from "react"
import { ProfileAvatarLink } from "@/app/components/ProfileLink"
import { CommentAuthorLine } from "@/app/components/comments/CommentAuthorLine"

type FeedCommentItemProps = {
  comment: any
  avatarClassName?: string
  stopPropagation?: boolean
}

function FeedCommentItem({
  comment,
  avatarClassName = "h-8 w-8 shrink-0 rounded-full object-cover",
  stopPropagation = false,
}: FeedCommentItemProps) {
  const userId = String(comment.user_id ?? "")
  const username = comment.profiles?.username

  return (
    <div className="flex items-start gap-2">
      <ProfileAvatarLink
        userId={userId}
        username={username}
        src={comment.profiles?.avatar_url}
        imgClassName={avatarClassName}
        stopPropagation={stopPropagation}
      />
      <div className="min-w-0 flex-1">
        <CommentAuthorLine
          userId={userId}
          username={username}
          createdAt={comment.created_at}
          stopPropagation={stopPropagation}
        />
        <p className="break-words text-sm text-white">{comment.content}</p>
      </div>
    </div>
  )
}

export default memo(FeedCommentItem)
