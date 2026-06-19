"use client"

import type { MouseEvent, ReactNode } from "react"
import {
  formatEngagementCount,
  formatEngagementCountAccessible,
} from "@/lib/formatEngagementCount"

type EngagementCountButtonProps = {
  icon: ReactNode
  count: number
  ariaLabel: string
  onClick: (e: MouseEvent<HTMLButtonElement>) => void
  disabled?: boolean
  /** `boxed` — feed-style pill; `inline` — profile/trade text row */
  variant?: "boxed" | "inline"
  className?: string
  countClassName?: string
}

export default function EngagementCountButton({
  icon,
  count,
  ariaLabel,
  onClick,
  disabled = false,
  variant = "inline",
  className = "",
  countClassName = "text-xs tabular-nums",
}: EngagementCountButtonProps) {
  const display = formatEngagementCount(count)
  const accessible = formatEngagementCountAccessible(count)
  const abbreviated = display !== accessible

  const variantClass =
    variant === "boxed"
      ? "inline-flex h-9 min-w-9 shrink-0 items-center justify-center gap-1 whitespace-nowrap rounded-lg bg-white/5 px-2.5 text-sm text-gray-300 transition hover:bg-white/10 hover:text-white disabled:opacity-50"
      : "inline-flex shrink-0 items-center gap-1 whitespace-nowrap text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      aria-label={`${ariaLabel}, ${accessible}`}
      title={abbreviated ? accessible : undefined}
      className={`${variantClass} ${className}`.trim()}
    >
      <span className="shrink-0 leading-none" aria-hidden>
        {icon}
      </span>
      <span className={countClassName}>{display}</span>
    </button>
  )
}
