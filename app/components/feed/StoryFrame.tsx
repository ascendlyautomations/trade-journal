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
  footer?: ReactNode
  /** When true, reserve space at the bottom for footer content (e.g. story reply input). */
  hasFooter?: boolean
  children?: ReactNode
}

export default function StoryFrame({
  profile,
  imageUrl,
  timestamp,
  className = "",
  imageKey,
  headerRight,
  footer,
  hasFooter = Boolean(footer),
  children,
}: StoryFrameProps) {
  const username = profile.username?.trim() || "User"
  const storyAge = storyTimeAgo(timestamp ?? new Date().toISOString())

  return (
    <div
      className={`relative flex flex-col overflow-hidden bg-black ${className}`}
    >
      <div className="absolute left-3 right-14 top-3 z-[2] flex items-center gap-2.5">
        <ProfileAvatarImg
          src={profile.avatar_url}
          className="h-8 w-8 shrink-0 ring-2 ring-emerald-400/40"
        />
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

      <div
        className={`absolute inset-0 z-0 flex items-center justify-center bg-black pt-11 ${
          hasFooter ? "pb-[4.75rem]" : ""
        }`}
      >
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

      {footer ? (
        <div className="absolute bottom-0 left-0 right-0 z-[3]">{footer}</div>
      ) : null}

      {children}
    </div>
  )
}
