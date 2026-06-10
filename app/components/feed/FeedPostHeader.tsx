"use client"

import { memo } from "react"
import Link from "next/link"
import { profilePath } from "@/lib/profileRoutes"

type FeedPostHeaderProps = {
  userId: string
  avatarUrl: string | null
  username: string
  preview?: boolean
}

function FeedPostHeader({
  userId,
  avatarUrl,
  username,
  preview = false,
}: FeedPostHeaderProps) {
  const className =
    "flex items-center gap-3 p-4 border-b border-white/5 transition-colors" +
    (preview ? "" : " hover:bg-white/5")

  const inner = (
    <>
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
    </>
  )

  if (preview) {
    return <div className={className}>{inner}</div>
  }

  return (
    <Link
      href={profilePath({ username, id: userId })}
      onClick={(e) => e.stopPropagation()}
      className={className}
    >
      {inner}
    </Link>
  )
}

export default memo(FeedPostHeader)
