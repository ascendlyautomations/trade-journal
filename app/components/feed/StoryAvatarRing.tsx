"use client"

import type { StoryBarProfile } from "@/lib/activeStories"
import { isImageUrlLoaded, markImageUrlLoaded } from "@/lib/imageUrlCache"

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
  imageClassName = "h-full w-full rounded-full object-cover",
  priority = false,
}: StoryAvatarRingProps) {
  const avatarUrl = profile.avatar_url?.trim() || ""
  const avatar = avatarUrl ? (
    <img
      src={avatarUrl}
      alt=""
      loading={priority || isImageUrlLoaded(avatarUrl) ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : undefined}
      className={imageClassName}
      onLoad={() => {
        if (avatarUrl) markImageUrlLoaded(avatarUrl)
      }}
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
