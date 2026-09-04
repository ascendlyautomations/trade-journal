"use client"

import { memo, useMemo, useRef, useState } from "react"
import ConfirmModal from "@/app/components/ui/ConfirmModal"
import { NAVBAR_HEIGHT_CLASS } from "@/app/components/ui/DetailModalShell"
import type { StoryBarProfile } from "./FeedStoriesBar"
import StoryFrame from "./StoryFrame"
import StoryReplyInput from "./StoryReplyInput"

type StorySlide = {
  id: string
  image_url: string
  created_at: string
}

type FeedStoryViewerProps = {
  activeStoryUser: string
  users: StoryBarProfile[]
  storiesByUser: Record<string, StorySlide[]>
  currentStories: StorySlide[]
  currentStoryIndex: number
  currentStory: StorySlide
  currentUserId?: string | null
  canGoPrevSlide: boolean
  canGoNextSlide: boolean
  canGoPrevUser: boolean
  canGoNextUser: boolean
  onClose: () => void
  onPrevSlide: () => void
  onNextSlide: () => void
  onPrevUser: () => void
  onNextUser: () => void
  onStoryReplyError?: (message: string) => void
  /** Owner-only — deletes via Supabase and updates parent story state. */
  onDeleteStory?: (storyId: string) => Promise<boolean>
}

const SWIPE_THRESHOLD_PX = 48

const STORY_FRAME_HEIGHT =
  "h-[calc(100dvh-var(--navbar-height,4rem)-2rem)] max-h-[calc(100dvh-var(--navbar-height,4rem)-2rem)] sm:h-[min(700px,calc(100dvh-var(--navbar-height,4rem)-2rem))]"

function ChevronLeftIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      aria-hidden
    >
      <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function ChevronRightIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      aria-hidden
    >
      <path d="M9 18l6-6-6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

const userNavButtonClass =
  "flex shrink-0 items-center gap-1.5 rounded-full border border-white/15 bg-black/55 px-3 py-2 text-sm font-medium text-white shadow-lg shadow-black/40 backdrop-blur-sm transition duration-200 hover:scale-[1.02] hover:border-white/30 hover:bg-white/15 active:scale-95 disabled:pointer-events-none disabled:opacity-30 md:px-4 md:py-2.5"

function NeighborStoryPreview({
  profile,
  coverUrl,
  onClick,
  side,
}: {
  profile: StoryBarProfile
  coverUrl: string | null
  onClick: () => void
  side: "prev" | "next"
}) {
  const username = profile.username?.trim() || "User"

  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`View ${username}'s story`}
      className={`group relative hidden ${STORY_FRAME_HEIGHT} w-[100px] shrink-0 overflow-hidden rounded-xl border border-white/10 opacity-60 transition duration-300 hover:opacity-80 md:block lg:w-[120px] ${
        side === "prev" ? "origin-right scale-[0.88]" : "origin-left scale-[0.88]"
      }`}
    >
      {coverUrl ? (
        <img
          src={coverUrl}
          alt=""
          className="h-full w-full object-cover brightness-75 transition group-hover:brightness-90"
          draggable={false}
        />
      ) : (
        <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-blue-900/40 to-emerald-900/40" />
      )}
      <div className="absolute inset-0 bg-black/35" />
      <p className="absolute bottom-3 left-0 right-0 truncate px-2 text-center text-[11px] font-medium text-white/90">
        {username}
      </p>
    </button>
  )
}

function StoryViewerOverflowMenu({
  onDelete,
}: {
  onDelete: () => void
}) {
  const [open, setOpen] = useState(false)

  return (
    <div className="relative">
      <button
        type="button"
        aria-label="Story options"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="rounded-full border border-white/10 bg-black/70 px-2.5 py-1 text-sm font-semibold text-white transition hover:border-white/25 hover:bg-black/90"
      >
        ···
      </button>
      {open ? (
        <>
          <button
            type="button"
            aria-label="Close story menu"
            className="fixed inset-0 z-[10004] cursor-default"
            onClick={() => setOpen(false)}
          />
          <div className="absolute right-0 top-full z-[10005] mt-1 min-w-[10rem] overflow-hidden rounded-lg border border-white/10 bg-[#1e293b] py-1 shadow-xl shadow-black/40">
            <button
              type="button"
              className="block w-full px-3 py-2 text-left text-sm text-red-300 transition hover:bg-white/10"
              onClick={() => {
                setOpen(false)
                onDelete()
              }}
            >
              Delete Story
            </button>
          </div>
        </>
      ) : null}
    </div>
  )
}

function FeedStoryViewer({
  activeStoryUser,
  users,
  storiesByUser,
  currentStory,
  currentUserId,
  canGoPrevSlide,
  canGoNextSlide,
  canGoPrevUser,
  canGoNextUser,
  onClose,
  onPrevSlide,
  onNextSlide,
  onPrevUser,
  onNextUser,
  onStoryReplyError,
  onDeleteStory,
}: FeedStoryViewerProps) {
  const touchStartX = useRef<number | null>(null)
  const touchStartY = useRef<number | null>(null)
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const activeProfile = useMemo(
    () => users.find((u) => u.id === activeStoryUser),
    [activeStoryUser, users]
  )

  const activeUserIndex = useMemo(
    () => users.findIndex((u) => u.id === activeStoryUser),
    [activeStoryUser, users]
  )

  const prevProfile = activeUserIndex > 0 ? users[activeUserIndex - 1] : null
  const nextProfile =
    activeUserIndex >= 0 && activeUserIndex < users.length - 1
      ? users[activeUserIndex + 1]
      : null

  const prevCoverUrl =
    prevProfile != null
      ? (storiesByUser[prevProfile.id]?.[0]?.image_url ?? null)
      : null
  const nextCoverUrl =
    nextProfile != null
      ? (storiesByUser[nextProfile.id]?.[0]?.image_url ?? null)
      : null

  const showStoryReply =
    currentUserId != null && currentUserId !== activeStoryUser

  const isOwner =
    currentUserId != null &&
    currentUserId === activeStoryUser &&
    onDeleteStory != null

  async function handleConfirmDelete() {
    if (!onDeleteStory) return
    setDeleting(true)
    try {
      const ok = await onDeleteStory(currentStory.id)
      if (ok) {
        setDeleteConfirmOpen(false)
      }
    } finally {
      setDeleting(false)
    }
  }

  function handleTouchStart(e: React.TouchEvent) {
    touchStartX.current = e.touches[0]?.clientX ?? null
    touchStartY.current = e.touches[0]?.clientY ?? null
  }

  function handleTouchEnd(e: React.TouchEvent) {
    const startX = touchStartX.current
    const startY = touchStartY.current
    touchStartX.current = null
    touchStartY.current = null

    if (startX == null || startY == null) return

    const endX = e.changedTouches[0]?.clientX ?? startX
    const endY = e.changedTouches[0]?.clientY ?? startY
    const deltaX = endX - startX
    const deltaY = endY - startY

    if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) return
    if (Math.abs(deltaY) > Math.abs(deltaX)) return

    if (deltaX < 0) {
      if (canGoNextSlide) onNextSlide()
      else if (canGoNextUser) onNextUser()
    } else if (canGoPrevSlide) {
      onPrevSlide()
    } else if (canGoPrevUser) {
      onPrevUser()
    }
  }

  if (!activeProfile) return null

  return (
    <>
      <div
        className={`fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS} z-[9999] flex items-start justify-center bg-black/95 px-2 pt-4 pb-[max(1rem,var(--safe-area-bottom))] md:px-6 md:pt-5`}
        role="dialog"
        aria-modal="true"
        aria-label="Stories"
      >
        <button
          type="button"
          aria-label="Previous user's story"
          onClick={onPrevUser}
          disabled={!canGoPrevUser}
          className={`absolute left-2 top-1/2 z-[10003] -translate-y-1/2 md:left-4 ${userNavButtonClass}`}
        >
          <ChevronLeftIcon className="h-5 w-5" />
          <span className="hidden sm:inline">Previous</span>
        </button>

        <button
          type="button"
          aria-label="Next user's story"
          onClick={onNextUser}
          disabled={!canGoNextUser}
          className={`absolute right-2 top-1/2 z-[10003] -translate-y-1/2 md:right-4 ${userNavButtonClass}`}
        >
          <span className="hidden sm:inline">Next</span>
          <ChevronRightIcon className="h-5 w-5" />
        </button>

        <div className="flex max-w-[min(100vw,920px)] items-center justify-center gap-2 md:gap-4">
          {prevProfile ? (
            <NeighborStoryPreview
              profile={prevProfile}
              coverUrl={prevCoverUrl}
              onClick={onPrevUser}
              side="prev"
            />
          ) : (
            <div className="hidden w-[100px] shrink-0 md:block lg:w-[120px]" aria-hidden />
          )}

          <StoryFrame
            key={activeStoryUser}
            profile={activeProfile}
            imageUrl={currentStory.image_url}
            imageKey={currentStory.id}
            timestamp={currentStory.created_at}
            hasFooter={showStoryReply}
            className={`relative ${STORY_FRAME_HEIGHT} w-full max-w-lg transition-opacity duration-300 sm:w-[400px] sm:rounded-2xl sm:border sm:border-white/10`}
            headerRight={
              <div className="flex items-center gap-2">
                {isOwner ? (
                  <StoryViewerOverflowMenu
                    onDelete={() => setDeleteConfirmOpen(true)}
                  />
                ) : null}
                <button
                  type="button"
                  aria-label="Close stories"
                  onClick={onClose}
                  className="rounded-full border border-white/10 bg-black/70 px-3 py-1 text-xs text-white transition hover:border-white/25 hover:bg-black/90"
                >
                  Esc
                </button>
              </div>
            }
            footer={
              showStoryReply && currentUserId ? (
                <StoryReplyInput
                  currentUserId={currentUserId}
                  storyOwnerId={activeStoryUser}
                  storyOwnerUsername={activeProfile.username}
                  story={{
                    id: currentStory.id,
                    image_url: currentStory.image_url,
                  }}
                  onError={onStoryReplyError}
                />
              ) : null
            }
          >
            <div
              className="absolute inset-0 z-[1]"
              onTouchStart={handleTouchStart}
              onTouchEnd={handleTouchEnd}
            >
              <button
                type="button"
                aria-label="Previous slide"
                onClick={() => {
                  if (canGoPrevSlide) onPrevSlide()
                  else if (canGoPrevUser) onPrevUser()
                }}
                className="absolute inset-y-0 left-0 w-[30%] cursor-pointer"
              />
              <button
                type="button"
                aria-label="Next slide"
                onClick={() => {
                  if (canGoNextSlide) onNextSlide()
                  else if (canGoNextUser) onNextUser()
                }}
                className="absolute inset-y-0 right-0 w-[30%] cursor-pointer"
              />
            </div>
          </StoryFrame>

          {nextProfile ? (
            <NeighborStoryPreview
              profile={nextProfile}
              coverUrl={nextCoverUrl}
              onClick={onNextUser}
              side="next"
            />
          ) : (
            <div className="hidden w-[100px] shrink-0 md:block lg:w-[120px]" aria-hidden />
          )}
        </div>
      </div>

      <ConfirmModal
        open={deleteConfirmOpen}
        title="Delete this story?"
        description="This story will be removed for everyone. This can't be undone."
        confirmLabel="Delete"
        cancelLabel="Cancel"
        destructive
        loading={deleting}
        loadingLabel="Deleting…"
        onCancel={() => {
          if (!deleting) setDeleteConfirmOpen(false)
        }}
        onConfirm={handleConfirmDelete}
      />
    </>
  )
}

export default memo(FeedStoryViewer)
