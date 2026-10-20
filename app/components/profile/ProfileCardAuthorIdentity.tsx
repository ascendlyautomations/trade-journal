"use client"

import type { ReactNode } from "react"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"

export type ProfileCardAuthorIdentityProps = {
  username?: string | null
  avatarUrl?: string | null
  meta: ReactNode
  /** Matches existing profile trade/post card avatar sizing. */
  avatarClassName?: string
}

/**
 * Author row (avatar + handle + meta) for profile Trades/Posts cards.
 * Uses the same ProfileAvatarImg pipeline as Messages and FeedPostHeader.
 */
export default function ProfileCardAuthorIdentity({
  username,
  avatarUrl,
  meta,
  avatarClassName = "h-9 w-9 shrink-0 ring-2 ring-white/10 md:h-10 md:w-10",
}: ProfileCardAuthorIdentityProps) {
  return (
    <>
      <ProfileAvatarImg src={avatarUrl} className={avatarClassName} />
      <div className="min-w-0">
        <p className="truncate text-sm font-semibold text-white">
          {username?.trim() || "User"}
        </p>
        {meta}
      </div>
    </>
  )
}
