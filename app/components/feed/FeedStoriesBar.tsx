"use client"

import type { ChangeEvent } from "react"
import { memo, useMemo } from "react"
import type { StoryBarProfile } from "@/lib/activeStories"
import StoryAvatarRing from "./StoryAvatarRing"

export type { StoryBarProfile }

type FeedStoriesBarProps = {
  currentUser: StoryBarProfile | null
  currentUserHasStory: boolean
  users: StoryBarProfile[]
  onStoryUpload: (e: ChangeEvent<HTMLInputElement>) => void
  onOpenStory: (userId: string) => void
}

function openStoryUpload() {
  document.getElementById("storyUploadInput")?.click()
}

function StoryPlusBadge({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label="Add story"
      onClick={(e) => {
        e.stopPropagation()
        onClick()
      }}
      className="tt-mobile-web-hit-slop absolute -bottom-0.5 -right-0.5 z-10 flex h-5 w-5 items-center justify-center rounded-full border-2 border-[#0f172a] bg-emerald-500 text-[13px] font-bold leading-none text-white shadow-md transition hover:bg-emerald-400 active:scale-95"
    >
      +
    </button>
  )
}

function MyStoryItem({
  profile,
  hasActiveStory,
  onOpenStory,
}: {
  profile: StoryBarProfile
  hasActiveStory: boolean
  onOpenStory: (userId: string) => void
}) {
  function handleAvatarClick() {
    if (hasActiveStory) {
      onOpenStory(profile.id)
      return
    }
    openStoryUpload()
  }

  return (
    <div className="flex shrink-0 flex-col items-center text-left">
      <div className="relative">
        <button
          type="button"
          onClick={handleAvatarClick}
          className="cursor-pointer rounded-full outline-none transition hover:opacity-90 focus-visible:ring-2 focus-visible:ring-emerald-400/60"
          aria-label={hasActiveStory ? "View your story" : "Add story"}
        >
          <StoryAvatarRing
            profile={profile}
            hasActiveStory={hasActiveStory}
            sizeClassName="h-16 w-16 max-md:h-[68px] max-md:w-[68px]"
          />
        </button>
        <StoryPlusBadge onClick={openStoryUpload} />
      </div>
      <p className="mt-1 max-w-[4.5rem] truncate text-center text-xs text-gray-200 max-md:max-w-[72px] max-md:text-[11px] max-md:text-[color:var(--tt-text,#f0f3f6)]">
        {hasActiveStory
          ? profile.username?.trim() || "Your story"
          : "Add Story"}
      </p>
    </div>
  )
}

function FeedStoriesBar({
  currentUser,
  currentUserHasStory,
  users,
  onStoryUpload,
  onOpenStory,
}: FeedStoriesBarProps) {
  const otherUsers = useMemo(
    () =>
      currentUser
        ? users.filter((u) => u.id !== currentUser.id)
        : users,
    [currentUser, users]
  )

  return (
    <>
      <input
        id="storyUploadInput"
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => void onStoryUpload(e)}
      />
      <div className="tt-mobile-web-hscroll mb-4 flex items-start gap-4 overflow-x-auto pb-3 max-md:mb-2 max-md:gap-4 max-md:px-1 max-md:pb-2">
        {currentUser ? (
          <MyStoryItem
            profile={currentUser}
            hasActiveStory={currentUserHasStory}
            onOpenStory={onOpenStory}
          />
        ) : null}

        {otherUsers.map((u) => (
          <button
            key={u.id}
            type="button"
            onClick={() => onOpenStory(u.id)}
            className="flex shrink-0 cursor-pointer flex-col items-center text-left"
          >
            <StoryAvatarRing
              profile={u}
              hasActiveStory
              sizeClassName="h-16 w-16 max-md:h-[68px] max-md:w-[68px]"
            />
            <p className="mt-1 max-w-[4.5rem] truncate text-center text-xs text-gray-200 max-md:max-w-[72px] max-md:text-[11px] max-md:text-[color:var(--tt-text,#f0f3f6)]">
              {u.username?.trim() || "User"}
            </p>
          </button>
        ))}

        {otherUsers.length === 0 ? (
          <div className="min-w-0 flex-1 px-2 py-1">
            <p className="text-sm font-medium text-gray-300 max-md:text-[color:var(--tt-text,#f0f3f6)]">
              No Stories Yet
            </p>
            <p className="mt-0.5 text-xs text-gray-400 max-md:text-[color:var(--tt-text-muted,#c0cad6)]">
              Stories from traders you follow will appear here.
            </p>
          </div>
        ) : null}
      </div>
    </>
  )
}

export default memo(FeedStoriesBar)
