"use client"

import type { StoryBarProfile } from "@/lib/activeStories"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"

type StoryAvatarRingProps = {
  profile: Pick<StoryBarProfile, "avatar_url">
  hasActiveStory: boolean
  sizeClassName?: string
  imageClassName?: string
  /** Eager-load for above-the-fold profile header avatars. */
  priority?: boolean
  /** Fixed transform width to avoid duplicate avatar requests across sizes. */
  displaySizePx?: number
}

export default function StoryAvatarRing({
  profile,
  hasActiveStory,
  sizeClassName = "h-16 w-16",
  imageClassName = "h-full w-full",
  priority = false,
  displaySizePx,
}: StoryAvatarRingProps) {
  const avatar = (
    <ProfileAvatarImg
      src={profile.avatar_url}
      className={imageClassName}
      priority={priority}
      displaySizePx={displaySizePx}
    />
  )

  if (hasActiveStory) {
    return (
      <div
        className={`${sizeClassName} rounded-full bg-gradient-to-tr from-sky-300 to-emerald-300 p-[2px] shadow-[0_0_0_2px_rgba(125,211,252,0.25)]`}
      >
        <div className="h-full w-full overflow-hidden rounded-full">{avatar}</div>
      </div>
    )
  }

  return (
    <div className={`${sizeClassName} overflow-hidden rounded-full ring-2 ring-white/15`}>
      {avatar}
    </div>
  )
}
