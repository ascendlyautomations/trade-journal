"use client"

import { memo } from "react"
import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
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
    "flex cursor-pointer items-center gap-3 border-b border-white/5 p-4 transition-colors" +
    (preview ? "" : " hover:bg-white/5")

  const inner = (
    <>
      <ProfileAvatarImg
        src={avatarUrl}
        className="h-10 w-10 shrink-0 ring-2 ring-white/10"
      />
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
