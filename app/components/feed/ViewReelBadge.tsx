"use client"

import { memo, type MouseEvent } from "react"

type ViewReelBadgeProps = {
  onClick: (event: MouseEvent<HTMLButtonElement>) => void
  className?: string
}

function ViewReelBadge({ onClick, className = "" }: ViewReelBadgeProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="View reel"
      className={`inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-full border border-purple-500/30 bg-purple-500/15 px-2.5 py-1 text-[10px] font-medium leading-none text-purple-400 transition hover:bg-purple-500/25 hover:text-purple-300 sm:text-xs ${className}`.trim()}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-3 w-3 shrink-0 opacity-90"
        fill="currentColor"
        viewBox="0 0 24 24"
        aria-hidden
      >
        <path d="M8 5.14v14.72a1 1 0 0 0 1.5.86l11.04-7.36a1 1 0 0 0 0-1.72L9.5 4.28a1 1 0 0 0-1.5.86z" />
      </svg>
      View Reel
    </button>
  )
}

export default memo(ViewReelBadge)
