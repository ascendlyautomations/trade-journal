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
}

export default function StoryAvatarRing({
  profile,
  hasActiveStory,
  sizeClassName = "h-16 w-16",
  imageClassName = "h-full w-full",
  priority = false,
}: StoryAvatarRingProps) {
  const avatar = (
    <ProfileAvatarImg
      src={profile.avatar_url}
      className={imageClassName}
      priority={priority}
    />
  )

  if (hasActiveStory) {
    return (
      <div
        className={`${sizeClassName} rounded-full border-2 border-emerald-400 p-[2px] ring-2 ring-emerald-400/30`}
      >
        {avatar}
      </div>
    )
  }

  return (
    <div className={`${sizeClassName} overflow-hidden rounded-full ring-2 ring-white/15`}>
      {avatar}
    </div>
  )
}
