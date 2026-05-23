"use client"

import { memo, useMemo } from "react"
import type { StoryBarProfile } from "./FeedStoriesBar"

type StorySlide = {
  id: string
  image_url: string
}

type FeedStoryViewerProps = {
  activeStoryUser: string
  users: StoryBarProfile[]
  currentStories: StorySlide[]
  currentStoryIndex: number
  currentStory: StorySlide
  onClose: () => void
  onPrev: () => void
  onNext: () => void
}

function FeedStoryViewer({
  activeStoryUser,
  users,
  currentStories,
  currentStoryIndex,
  currentStory,
  onClose,
  onPrev,
  onNext,
}: FeedStoryViewerProps) {
  const activeStoryUsername = useMemo(() => {
    const profile = users.find((u) => u.id === activeStoryUser)
    return profile?.username?.trim() || "User"
  }, [activeStoryUser, users])

  return (
    <div
      className="fixed inset-0 z-[9999] bg-black flex items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-label="Stories"
    >
      <div
        className="relative w-[400px] h-[700px] bg-black rounded-2xl overflow-hidden flex items-center justify-center"
        style={{ margin: 0, padding: 0 }}
      >
        <button
          type="button"
          aria-label="Close stories"
          onClick={onClose}
          className="absolute right-3 top-3 z-[10000] rounded-full bg-black/70 px-3 py-1 text-xs text-white hover:bg-black/90"
        >
          Esc
        </button>

        <div className="absolute left-3 top-3 z-[10000] text-sm text-white">
          {activeStoryUsername}
        </div>

        <div className="absolute top-2 left-2 right-2 flex gap-1 z-[10000]">
          {currentStories.map((s, i) => (
            <div
              key={s.id}
              className={`h-[3px] flex-1 rounded ${
                i <= currentStoryIndex ? "bg-zinc-200" : "bg-zinc-500/40"
              }`}
            />
          ))}
        </div>

        <div className="absolute inset-0 z-0 flex h-full w-full items-center justify-center bg-black">
          <img
            src={currentStory.image_url}
            alt=""
            loading="lazy"
            decoding="async"
            className="max-w-full max-h-full object-contain block"
            draggable={false}
          />
        </div>

        <button
          type="button"
          aria-label="Previous story"
          onClick={onPrev}
          className="absolute left-2 top-1/2 z-[10000] -translate-y-1/2 rounded-full bg-black/40 px-3 py-1 text-3xl text-white transition hover:scale-110"
        >
          ‹
        </button>

        <button
          type="button"
          aria-label="Next story"
          onClick={onNext}
          className="absolute right-2 top-1/2 z-[10000] -translate-y-1/2 rounded-full bg-black/40 px-3 py-1 text-3xl text-white transition hover:scale-110"
        >
          ›
        </button>
      </div>
    </div>
  )
}

export default memo(FeedStoryViewer)
