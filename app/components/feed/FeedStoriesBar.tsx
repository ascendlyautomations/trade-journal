"use client"

import type { ChangeEvent } from "react"
import { memo } from "react"

export type StoryBarProfile = {
  id: string
  username?: string | null
  avatar_url?: string | null
}

type FeedStoriesBarProps = {
  users: StoryBarProfile[]
  onStoryUpload: (e: ChangeEvent<HTMLInputElement>) => void
  onOpenStory: (userId: string) => void
}

function FeedStoriesBar({ users, onStoryUpload, onOpenStory }: FeedStoriesBarProps) {
  return (
    <>
      <input
        id="storyUploadInput"
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => void onStoryUpload(e)}
      />
      <div className="flex items-center gap-4 overflow-x-auto pb-3 mb-4">
        <button
          type="button"
          onClick={() => document.getElementById("storyUploadInput")?.click()}
          className="flex flex-col items-center shrink-0 cursor-pointer text-left"
        >
          <div className="w-16 h-16 rounded-full bg-green-500 flex items-center justify-center text-2xl text-white font-light leading-none hover:bg-green-600 transition-colors">
            +
          </div>
          <p className="text-xs mt-1 text-gray-300">Add</p>
        </button>

        {users.map((u) => (
          <button
            key={u.id}
            type="button"
            onClick={() => onOpenStory(u.id)}
            className="flex flex-col items-center shrink-0 cursor-pointer text-left"
          >
            {u.avatar_url ? (
              <img
                src={u.avatar_url}
                alt=""
                loading="lazy"
                decoding="async"
                className="w-16 h-16 rounded-full object-cover border-2 border-emerald-400 ring-2 ring-emerald-400/30"
              />
            ) : (
              <div
                className="w-16 h-16 rounded-full border-2 border-emerald-400 bg-gradient-to-br from-blue-500/40 to-emerald-500/40"
                aria-hidden
              />
            )}
            <p className="text-xs mt-1 max-w-[4.5rem] truncate text-center text-gray-200">
              {u.username?.trim() || "User"}
            </p>
          </button>
        ))}
      </div>
    </>
  )
}

export default memo(FeedStoriesBar)
