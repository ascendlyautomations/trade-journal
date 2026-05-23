"use client"

import { memo } from "react"
import Link from "next/link"

type FeedPostHeaderProps = {
  userId: string
  avatarUrl: string | null
  username: string
}

function FeedPostHeader({ userId, avatarUrl, username }: FeedPostHeaderProps) {
  return (
    <Link
      href={`/profile/${userId}`}
      onClick={(e) => e.stopPropagation()}
      className="flex items-center gap-3 p-4 border-b border-white/5 hover:bg-white/5 transition-colors"
    >
      {avatarUrl ? (
        <img
          src={avatarUrl}
          alt=""
          loading="lazy"
          decoding="async"
          className="w-10 h-10 rounded-full object-cover ring-2 ring-white/10 shrink-0"
        />
      ) : (
        <div
          className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40 ring-2 ring-white/10 shrink-0"
          aria-hidden
        />
      )}
      <span className="font-semibold text-sm sm:text-base truncate text-white">
        {username}
      </span>
    </Link>
  )
}

export default memo(FeedPostHeader)
