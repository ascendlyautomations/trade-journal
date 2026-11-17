"use client"

import type { ReactNode } from "react"
import type { StoryBarProfile } from "./FeedStoriesBar"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import StorageImage from "@/app/components/ui/StorageImage"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"
import {
  storyMediaIsVideo,
  type StoryTextOverlay,
} from "@/lib/activeStories"

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
  /** Load the visible slide immediately. Off by default so desktop stays lazy. */
  priority?: boolean
  textOverlays?: StoryTextOverlay[] | null
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
  priority = false,
  textOverlays = null,
  children,
}: StoryFrameProps) {
  const username = profile.username?.trim() || "User"
  const storyAge = storyTimeAgo(timestamp ?? new Date().toISOString())

  return (
    <div
      className={`relative flex flex-col overflow-hidden bg-[#0f172a] ${className}`}
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
        className={`absolute inset-0 z-0 flex items-center justify-center pt-11 ${
          hasFooter ? "pb-[4.75rem]" : ""
        }`}
      >
        {storyMediaIsVideo(imageUrl) ? (
          <video
            key={imageKey ?? imageUrl}
            src={imageUrl}
            className="block max-h-full max-w-full object-contain"
            playsInline
            muted
            autoPlay
            controls={false}
          />
        ) : (
          <StorageImage
            key={imageKey ?? imageUrl}
            src={imageUrl}
            originalSrc={imageUrl}
            preset="story"
            alt=""
            priority={priority}
            className="block max-h-full max-w-full animate-[storyFadeIn_0.28s_ease-out] object-contain"
            draggable={false}
          />
        )}
        {textOverlays?.map((overlay, index) => {
          const text = overlay.text?.trim()
          if (!text) return null
          const red = Math.round((overlay.red ?? 1) * 255)
          const green = Math.round((overlay.green ?? 1) * 255)
          const blue = Math.round((overlay.blue ?? 1) * 255)
          const alpha = overlay.alpha ?? 1
          return (
            <p
              key={overlay.id ?? `${index}-${text}`}
              className="pointer-events-none absolute z-[2] max-w-[80%] text-center text-sm font-semibold"
              style={{
                left: `${(overlay.x ?? 0.5) * 100}%`,
                top: `${(overlay.y ?? 0.5) * 100}%`,
                transform: `translate(-50%, -50%) scale(${overlay.scale ?? 1}) rotate(${overlay.rotation ?? 0}rad)`,
                color: `rgba(${red}, ${green}, ${blue}, ${alpha})`,
                background: overlay.background ? "rgba(0,0,0,0.45)" : undefined,
              }}
            >
              {text}
            </p>
          )
        })}
      </div>

      {footer ? (
        <div className="absolute bottom-0 left-0 right-0 z-[3]">{footer}</div>
      ) : null}

      {children}
    </div>
  )
}
