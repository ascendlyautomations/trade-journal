"use client"

import { memo } from "react"
import { ProfileUsernameLink } from "@/app/components/ProfileLink"
import { parseLeadingCommentMention } from "@/lib/commentReplyUx"

type CommentContentProps = {
  content: string
  mentionUserIdsByUsername?: Map<string, string>
  stopPropagation?: boolean
  className?: string
}

function CommentContent({
  content,
  mentionUserIdsByUsername,
  stopPropagation = false,
  className = "break-words text-sm text-white",
}: CommentContentProps) {
  const { username, body } = parseLeadingCommentMention(content)

  if (!username) {
    return <p className={className}>{content}</p>
  }

  const userId = mentionUserIdsByUsername?.get(username) ?? ""

  return (
    <p className={className}>
      {userId ? (
        <ProfileUsernameLink
          userId={userId}
          username={username}
          stopPropagation={stopPropagation}
          className="font-medium text-blue-400 hover:text-blue-300 hover:underline"
        >
          @{username}
        </ProfileUsernameLink>
      ) : (
        <span className="font-medium text-blue-400">@{username}</span>
      )}
      {body ? (
        <>
          {" "}
          {body}
        </>
      ) : null}
    </p>
  )
}

export default memo(CommentContent)
