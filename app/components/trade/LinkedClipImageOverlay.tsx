"use client"

import { memo, type MouseEvent } from "react"

type LinkedClipImageOverlayProps = {
  onClick: (event: MouseEvent<HTMLButtonElement>) => void
  className?: string
}

function LinkedClipImageOverlay({
  onClick,
  className = "",
}: LinkedClipImageOverlayProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Linked Clip"
      className={`inline-flex shrink-0 cursor-pointer items-center gap-2 rounded-full border border-white/25 bg-violet-500/35 px-3 py-1.5 text-xs font-semibold text-white shadow-lg shadow-black/45 backdrop-blur-md transition hover:border-white/35 hover:bg-violet-500/48 sm:px-3.5 sm:py-2 sm:text-sm ${className}`.trim()}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-3.5 w-3.5 shrink-0 sm:h-4 sm:w-4"
        fill="currentColor"
        viewBox="0 0 24 24"
        aria-hidden
      >
        <path d="M8 5.14v14.72a1 1 0 0 0 1.5.86l11.04-7.36a1 1 0 0 0 0-1.72L9.5 4.28a1 1 0 0 0-1.5.86z" />
      </svg>
      Linked Clip
    </button>
  )
}

export default memo(LinkedClipImageOverlay)
