"use client"

import { memo, useEffect, useRef } from "react"
import {
  LayoutGrid,
  MessageSquareText,
  PlaySquare,
  TrendingUp,
  Trophy,
} from "lucide-react"
import type { FeedContentFilter } from "./feedPostHelpers"

type FeedContentToggleProps = {
  contentType: FeedContentFilter
  onContentTypeChange: (contentType: FeedContentFilter) => void
}

const FILTER_ICONS: Record<
  FeedContentFilter,
  typeof LayoutGrid
> = {
  all: LayoutGrid,
  trades: TrendingUp,
  reels: PlaySquare,
  posts: MessageSquareText,
  achievements: Trophy,
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
    <div className="mb-4 flex w-full min-w-0 justify-center px-1 max-md:mb-2 max-md:justify-start max-md:px-0">
      {/*
        Keep options in one row. When the row is wider than the viewport,
        justify-center + ancestor overflow-x-hidden clipped the leftmost
        "All" control — anchor start and allow horizontal scroll instead.
      */}
      <div
        ref={scrollerRef}
        className="tt-mobile-web-hscroll flex max-w-full flex-nowrap justify-start gap-1 overflow-x-auto overscroll-x-contain bg-white/5 p-1 rounded-xl border border-white/10 sm:gap-2 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden max-md:gap-1 max-md:border-transparent max-md:bg-transparent max-md:p-0 max-md:px-1"
      >
        {options.map(({ id, label }) => {
          const Icon = FILTER_ICONS[id]
          return (
          <button
            key={id}
            type="button"
            data-feed-content-filter={id}
            onClick={() => onContentTypeChange(id)}
            aria-label={label}
            title={label}
            className={`inline-flex shrink-0 items-center justify-center rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors sm:px-4 sm:text-sm max-md:min-h-11 max-md:min-w-[52px] max-md:max-w-[4.75rem] max-md:flex-col max-md:gap-0.5 max-md:rounded-[10px] max-md:px-1 max-md:py-1 ${
              contentType === id
                ? "bg-blue-500 text-white shadow-sm max-md:bg-white/10 max-md:text-[color:var(--tt-text,#f0f3f6)] max-md:shadow-none"
                : "text-gray-400 hover:text-gray-200 max-md:text-[color:var(--tt-text-muted,#c0cad6)]"
            }`}
          >
            <Icon
              className="mb-0.5 hidden h-5 w-5 max-md:block"
              strokeWidth={contentType === id ? 2.1 : 1.75}
              aria-hidden
            />
            <span className="max-md:max-w-full max-md:truncate max-md:text-center max-md:text-[10px] max-md:leading-tight max-md:tracking-tight">
              {label}
            </span>
          </button>
          )
        })}
      </div>
    </div>
  )
}
export default memo(FeedContentToggle)
