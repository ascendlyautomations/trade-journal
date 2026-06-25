"use client"

import type { ReactNode } from "react"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"

type CommentFocusCompactStripProps = {
  userId: string
  username?: string | null
  avatarUrl?: string | null
  timestamp?: string | null
  meta?: ReactNode
  className?: string
  /** Mobile: tap strip to restore collapsed content (sets commentsFocused false). */
  onExpand?: () => void
}

/** Minimal author + meta row shown on mobile when comments are focused. */
export function CommentFocusCompactStrip({
  userId,
  username,
  avatarUrl,
  timestamp,
  meta,
  className = "",
  onExpand,
}: CommentFocusCompactStripProps) {
  const timeLabel = formatSocialTimestamp(timestamp)
  const avatarSrc =
    avatarUrl != null && String(avatarUrl).trim() !== ""
      ? String(avatarUrl).trim()
      : "/default-avatar.png"
  const displayName = username?.trim() || "User"

  const inner = (
    <>
      {onExpand ? (
        <img
          src={avatarSrc}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-8 w-8 shrink-0 rounded-full object-cover ring-2 ring-white/10"
          onError={(e) => {
            e.currentTarget.src = "/default-avatar.png"
          }}
        />
      ) : (
        <ProfileAvatarLink
          userId={userId}
          username={username}
          src={avatarUrl}
          imgClassName="h-8 w-8 shrink-0 rounded-full object-cover ring-2 ring-white/10"
        />
      )}
      <div className="min-w-0 flex-1 text-left">
        <p className="truncate whitespace-nowrap text-xs text-gray-400">
          {onExpand ? (
            <span className="inline font-semibold text-white">{displayName}</span>
          ) : (
            <ProfileUsernameLink
              userId={userId}
              username={username}
              className="inline font-semibold text-white hover:text-gray-200"
            />
          )}
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
      {onExpand ? (
        <span
          className="shrink-0 text-[10px] text-gray-500"
          aria-hidden
        >
          ▼
        </span>
      ) : null}
    </>
  )

  if (onExpand) {
    return (
      <button
        type="button"
        onClick={onExpand}
        className={`flex w-full min-w-0 items-center gap-2.5 px-4 py-2.5 text-left transition hover:bg-white/5 active:bg-white/[0.07] ${className}`.trim()}
        aria-label="Show full content"
      >
        {inner}
      </button>
    )
  }

  return (
    <div className={`flex min-w-0 items-center gap-2.5 px-4 py-2.5 ${className}`.trim()}>
      {inner}
    </div>
  )
}
