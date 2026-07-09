"use client"

type CopyTradedBadgeProps = {
  className?: string
}

export default function CopyTradedBadge({ className = "" }: CopyTradedBadgeProps) {
  return (
    <span
      className={`rounded bg-violet-500/15 px-2 py-0.5 text-[11px] font-medium text-violet-200 ${className}`}
    >
      Copy Traded
    </span>
  )
}
