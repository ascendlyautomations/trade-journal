"use client"

import { memo, type MouseEvent } from "react"

type LinkedTradeBadgeProps = {
  onClick: (event: MouseEvent<HTMLButtonElement>) => void
  className?: string
}

function LinkedTradeBadge({ onClick, className = "" }: LinkedTradeBadgeProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="View linked trade"
      className={`inline-flex shrink-0 items-center gap-1 rounded-full bg-orange-500/90 px-2.5 py-1 text-[10px] font-medium leading-none text-white transition hover:bg-orange-500 sm:text-xs ${className}`.trim()}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-3 w-3 shrink-0 opacity-90"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        strokeWidth={2}
        aria-hidden
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="M3 17l6-6 4 4 8-8"
        />
      </svg>
      Linked Trade
    </button>
  )
}

export default memo(LinkedTradeBadge)
