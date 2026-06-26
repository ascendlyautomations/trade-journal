"use client"

import type { StoryBarProfile } from "@/lib/activeStories"

type StoryAvatarRingProps = {
  profile: Pick<StoryBarProfile, "avatar_url">
  hasActiveStory: boolean
  sizeClassName?: string
  imageClassName?: string
}

export default function StoryAvatarRing({
  profile,
  hasActiveStory,
  sizeClassName = "h-16 w-16",
  imageClassName = "h-full w-full rounded-full object-cover",
}: StoryAvatarRingProps) {
  const avatar = profile.avatar_url ? (
    <img
      src={profile.avatar_url}
      alt=""
      loading="lazy"
      decoding="async"
      className={imageClassName}
      onError={(e) => {
        e.currentTarget.src = "/default-avatar.png"
      }}
    />
  ) : (
    <div
      className={`${imageClassName} bg-gradient-to-br from-blue-500/40 to-emerald-500/40`}
      aria-hidden
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
