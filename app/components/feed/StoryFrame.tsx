"use client"

import type { ReactNode } from "react"
import type { StoryBarProfile } from "./FeedStoriesBar"

import { formatSocialTimestamp } from "@/lib/formatRelativeTime"

export function storyTimeAgo(iso: string): string {
  return formatSocialTimestamp(iso)
}

type StoryFrameProps = {
  profile: StoryBarProfile
  imageUrl: string
  /** ISO timestamp shown in header; defaults to now (preview). */
  timestamp?: string
  className?: string
  imageKey?: string
  headerRight?: ReactNode
  children?: ReactNode
}

export default function StoryFrame({
  profile,
  imageUrl,
  timestamp,
  className = "",
  imageKey,
  headerRight,
  children,
}: StoryFrameProps) {
  const username = profile.username?.trim() || "User"
  const storyAge = storyTimeAgo(timestamp ?? new Date().toISOString())

  return (
    <div
      className={`relative flex flex-col overflow-hidden bg-black ${className}`}
    >
      <div className="absolute left-3 right-14 top-3 z-[2] flex items-center gap-2.5">
        {profile.avatar_url ? (
          <img
            src={profile.avatar_url}
            alt=""
            className="h-8 w-8 shrink-0 rounded-full object-cover ring-2 ring-emerald-400/40"
            onError={(e) => {
              e.currentTarget.src = "/default-avatar.png"
            }}
          />
        ) : (
          <div className="h-8 w-8 shrink-0 rounded-full bg-gradient-to-br from-blue-500/50 to-emerald-500/50 ring-2 ring-emerald-400/40" />
        )}
        <p className="min-w-0 truncate text-sm font-medium text-white drop-shadow">
          <span>{username}</span>
          {storyAge ? (
            <span className="font-normal text-white/70"> • {storyAge}</span>
          ) : null}
        </p>
      </div>

      {headerRight ? (
        <div className="absolute right-3 top-3 z-[2]">{headerRight}</div>
      ) : null}

      <div className="absolute inset-0 z-0 flex items-center justify-center bg-black pt-11">
        <img
          key={imageKey ?? imageUrl}
          src={imageUrl}
          alt=""
          loading="lazy"
          decoding="async"
          className="block max-h-full max-w-full animate-[storyFadeIn_0.28s_ease-out] object-contain"
          draggable={false}
        />
      </div>

      {children}
    </div>
  )
}
