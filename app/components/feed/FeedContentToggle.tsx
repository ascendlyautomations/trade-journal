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
    { id: "posts", label: "Posts" },
  ]

  return (
    <div className="flex justify-center mb-4">
      <div className="flex gap-1 sm:gap-2 bg-white/5 p-1 rounded-xl border border-white/10">
        {options.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            onClick={() => onContentTypeChange(id)}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              contentType === id
                ? "bg-green-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            {label}
          </button>
        ))}
      </div>
    </div>
  )
}

export default memo(FeedContentToggle)
