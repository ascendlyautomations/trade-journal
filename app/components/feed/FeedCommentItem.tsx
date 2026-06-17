"use client"

import { memo } from "react"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"

type FeedCommentItemProps = {
  comment: any
}

function FeedCommentItem({ comment }: FeedCommentItemProps) {
  const userId = String(comment.user_id ?? "")
  const username = comment.profiles?.username

  return (
    <div className="flex items-start gap-2">
      <ProfileAvatarLink
        userId={userId}
        username={username}
        src={comment.profiles?.avatar_url}
        imgClassName="h-8 w-8 shrink-0 rounded-full object-cover"
      />
      <div className="min-w-0">
        <ProfileUsernameLink
          userId={userId}
          username={username}
          className="text-xs text-gray-400"
        />
        <p className="break-words text-sm text-white">{comment.content}</p>
      </div>
    </div>
  )
}

export default memo(FeedCommentItem)
