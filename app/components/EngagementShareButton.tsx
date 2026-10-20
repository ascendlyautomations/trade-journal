"use client"

import type { MouseEvent } from "react"

export const ENGAGEMENT_SHARE_BUTTON_CLASS =
  "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-white/5 text-gray-300 transition hover:bg-white/10 hover:text-white"

type EngagementShareButtonProps = {
  onClick: (e: MouseEvent<HTMLButtonElement>) => void
  ariaLabel?: string
  disabled?: boolean
  className?: string
}

/** Share control — same icon/size as feed detail modals (Posts, Clips, Achievements). */
export default function EngagementShareButton({
  onClick,
  ariaLabel = "Share",
  disabled = false,
  className = "",
}: EngagementShareButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={`${ENGAGEMENT_SHARE_BUTTON_CLASS} ${className}`.trim()}
      aria-label={ariaLabel}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-4 w-4"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        aria-hidden
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
        />
      </svg>
    </button>
  )
}
