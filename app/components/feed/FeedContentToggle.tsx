"use client"

import { memo } from "react"
import type { FeedContentFilter } from "./feedPostHelpers"

type FeedContentToggleProps = {
  contentType: FeedContentFilter
  onContentTypeChange: (contentType: FeedContentFilter) => void
}

function FeedContentToggle({
  contentType,
  onContentTypeChange,
}: FeedContentToggleProps) {
  const options: { id: FeedContentFilter; label: string }[] = [
    { id: "all", label: "All" },
    { id: "trades", label: "Trades" },
    { id: "reels", label: "Clips" },
    { id: "posts", label: "Posts" },
    { id: "achievements", label: "Achievements" },
  ]

  return (
    <div className="mb-4 flex w-full min-w-0 justify-center px-1">
      <div className="flex max-w-full flex-nowrap justify-center gap-1 bg-white/5 p-1 rounded-xl border border-white/10 sm:gap-2">
        {options.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            onClick={() => onContentTypeChange(id)}
            aria-label={id === "achievements" ? "Achievements" : undefined}
            title={id === "achievements" ? "Achievements" : undefined}
            className={`inline-flex shrink-0 items-center justify-center rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors sm:px-4 sm:text-sm ${
              contentType === id
                ? "bg-green-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            {id === "achievements" ? (
              <>
                <span className="text-base leading-none sm:hidden" aria-hidden>
                  🏆
                </span>
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
