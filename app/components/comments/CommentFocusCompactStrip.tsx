"use client"

import type { ReactNode } from "react"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { formatSocialCommentTime } from "@/lib/formatSocialCommentTime"

type CommentFocusCompactStripProps = {
  userId: string
  username?: string | null
  avatarUrl?: string | null
  timestamp?: string | null
  meta?: ReactNode
  className?: string
}

/** Minimal author + meta row shown on mobile when comments are focused. */
export function CommentFocusCompactStrip({
  userId,
  username,
  avatarUrl,
  timestamp,
  meta,
  className = "",
}: CommentFocusCompactStripProps) {
  const timeLabel = formatSocialCommentTime(timestamp)

  return (
    <div className={`flex min-w-0 items-center gap-2.5 px-4 py-2.5 ${className}`.trim()}>
      <ProfileAvatarLink
        userId={userId}
        username={username}
        src={avatarUrl}
        imgClassName="h-8 w-8 shrink-0 rounded-full object-cover ring-2 ring-white/10"
      />
      <div className="min-w-0 flex-1">
        <p className="truncate whitespace-nowrap text-xs text-gray-400">
          <ProfileUsernameLink
            userId={userId}
            username={username}
            className="inline font-semibold text-white hover:text-gray-200"
          />
          {timeLabel ? (
            <>
              <span aria-hidden="true" className="mx-1 text-gray-500">
                •
              </span>
              <time dateTime={timestamp ?? undefined} className="text-gray-500">
                {timeLabel}
              </time>
            </>
          ) : null}
        </p>
        {meta ? (
          <div className="mt-0.5 truncate text-xs font-medium text-gray-300">
            {meta}
          </div>
        ) : null}
      </div>
    </div>
  )
}
