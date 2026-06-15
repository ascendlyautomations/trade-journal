"use client"

import type { ChangeEvent } from "react"
import { memo, useMemo } from "react"

export type StoryBarProfile = {
  id: string
  username?: string | null
  avatar_url?: string | null
}

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
      className="absolute -bottom-0.5 -right-0.5 z-10 flex h-5 w-5 items-center justify-center rounded-full border-2 border-[#0f172a] bg-emerald-500 text-[13px] font-bold leading-none text-white shadow-md transition hover:bg-emerald-400 active:scale-95"
    >
      +
    </button>
  )
}

function StoryAvatar({
  profile,
  hasStoryRing,
}: {
  profile: StoryBarProfile
  hasStoryRing: boolean
}) {
  const avatar = profile.avatar_url ? (
    <img
      src={profile.avatar_url}
      alt=""
      loading="lazy"
      decoding="async"
      className="h-full w-full rounded-full object-cover"
      onError={(e) => {
        e.currentTarget.src = "/default-avatar.png"
      }}
    />
  ) : (
    <div
      className="h-full w-full rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40"
      aria-hidden
    />
  )

  if (hasStoryRing) {
    return (
      <div className="h-16 w-16 rounded-full border-2 border-emerald-400 p-[2px] ring-2 ring-emerald-400/30">
        {avatar}
      </div>
    )
  }

  return (
    <div className="h-16 w-16 overflow-hidden rounded-full ring-2 ring-white/15">
      {avatar}
    </div>
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
          <StoryAvatar profile={profile} hasStoryRing={hasActiveStory} />
        </button>
        <StoryPlusBadge onClick={openStoryUpload} />
      </div>
      <p className="mt-1 max-w-[4.5rem] truncate text-center text-xs text-gray-200">
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
      <div className="mb-4 flex items-center gap-4 overflow-x-auto pb-3">
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
            {u.avatar_url ? (
              <img
                src={u.avatar_url}
                alt=""
                loading="lazy"
                decoding="async"
                className="h-16 w-16 rounded-full border-2 border-emerald-400 object-cover ring-2 ring-emerald-400/30"
              />
            ) : (
              <div
                className="h-16 w-16 rounded-full border-2 border-emerald-400 bg-gradient-to-br from-blue-500/40 to-emerald-500/40 ring-2 ring-emerald-400/30"
                aria-hidden
              />
            )}
            <p className="mt-1 max-w-[4.5rem] truncate text-center text-xs text-gray-200">
              {u.username?.trim() || "User"}
            </p>
          </button>
        ))}

        {otherUsers.length === 0 ? (
          <div className="min-w-0 flex-1 px-2 py-1">
            <p className="text-sm font-medium text-gray-300">No Stories Yet</p>
            <p className="mt-0.5 text-xs text-gray-500">
              Stories from traders you follow will appear here.
            </p>
          </div>
        ) : null}
      </div>
    </>
  )
}

export default memo(FeedStoriesBar)
