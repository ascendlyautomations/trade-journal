"use client"

import { memo } from "react"

export type FeedMode = "global" | "following"

type FeedModeToggleProps = {
  mode: FeedMode
  onModeChange: (mode: FeedMode) => void
}

function FeedModeToggle({ mode, onModeChange }: FeedModeToggleProps) {
  return (
    <div className="flex justify-center mb-4">
      <div className="flex gap-1 sm:gap-2 bg-white/5 p-1 rounded-xl border border-white/10">
        <button
          type="button"
          onClick={() => onModeChange("following")}
          className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
            mode === "following"
              ? "bg-blue-500 text-white shadow-sm"
              : "text-gray-400 hover:text-gray-200"
          }`}
        >
          Following
        </button>

        <button
          type="button"
          onClick={() => onModeChange("global")}
          className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
            mode === "global"
              ? "bg-blue-500 text-white shadow-sm"
              : "text-gray-400 hover:text-gray-200"
          }`}
        >
          Global
        </button>
      </div>
    </div>
  )
}

export default memo(FeedModeToggle)
