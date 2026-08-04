"use client"

import { memo, useEffect, useRef } from "react"
import type { FeedContentFilter } from "./feedPostHelpers"

type FeedContentToggleProps = {
  contentType: FeedContentFilter
  onContentTypeChange: (contentType: FeedContentFilter) => void
}

function FeedContentToggle({
  contentType,
  onContentTypeChange,
}: FeedContentToggleProps) {
  const scrollerRef = useRef<HTMLDivElement | null>(null)
  const options: { id: FeedContentFilter; label: string }[] = [
    { id: "all", label: "All" },
    { id: "trades", label: "Trades" },
    { id: "reels", label: "Clips" },
    { id: "posts", label: "Posts" },
    { id: "achievements", label: "Achievements" },
  ]

  useEffect(() => {
    const root = scrollerRef.current
    if (!root) return
    const selected = root.querySelector<HTMLElement>(
      `[data-feed-content-filter="${contentType}"]`
    )
    if (!selected) return
    const rootRect = root.getBoundingClientRect()
    const selRect = selected.getBoundingClientRect()
    if (selRect.left < rootRect.left) {
      root.scrollLeft -= rootRect.left - selRect.left
    } else if (selRect.right > rootRect.right) {
      root.scrollLeft += selRect.right - rootRect.right
    }
  }, [contentType])

  return (
    <div className="mb-4 flex w-full min-w-0 justify-center px-1">
      {/*
        Keep options in one row. When the row is wider than the viewport,
        justify-center + ancestor overflow-x-hidden clipped the leftmost
        "All" control — anchor start and allow horizontal scroll instead.
      */}
      <div
        ref={scrollerRef}
        className="flex max-w-full flex-nowrap justify-start gap-1 overflow-x-auto overscroll-x-contain bg-white/5 p-1 rounded-xl border border-white/10 sm:gap-2 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
      >
        {options.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            data-feed-content-filter={id}
            onClick={() => onContentTypeChange(id)}
            aria-label={id === "achievements" ? "Achievements" : undefined}
            title={id === "achievements" ? "Achievements" : undefined}
            className={`inline-flex shrink-0 items-center justify-center rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors sm:px-4 sm:text-sm ${
              contentType === id
                ? "bg-blue-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            {id === "achievements" ? (
              <>
                <span className="sm:hidden">Achievements</span>
                <span className="hidden sm:inline">Achievements</span>
              </>
            ) : (
              label
            )}
          </button>
        ))}
      </div>
    </div>
  )
}
export default memo(FeedContentToggle)
