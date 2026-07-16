"use client"

import { ProfileUsernameLink } from "@/app/components/ProfileLink"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"

type CommentAuthorLineProps = {
  userId: string
  username?: string | null
  createdAt?: string | null
  className?: string
  usernameClassName?: string
  stopPropagation?: boolean
}

export function CommentAuthorLine({
  userId,
  username,
  createdAt,
  className = "truncate whitespace-nowrap text-xs text-gray-400",
  usernameClassName = "font-medium text-gray-400 hover:text-gray-300",
  stopPropagation = false,
}: CommentAuthorLineProps) {
  const timeLabel = formatSocialTimestamp(createdAt)

  return (
    <p className={className}>
      <ProfileUsernameLink
        userId={userId}
        username={username}
        className={`inline ${usernameClassName}`}
        stopPropagation={stopPropagation}
      />
      {timeLabel ? (
        <>
          <span aria-hidden="true" className="mx-1 text-gray-400">
            •
          </span>
          <time dateTime={createdAt ?? undefined} className="text-gray-400">
            {timeLabel}
          </time>
        </>
      ) : null}
    </p>
  )
}
