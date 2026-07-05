"use client"

import { cn } from "@/app/components/ui/cn"

export type PerformanceShareButtonProps = {
  onClick: () => void
  className?: string
  /** `dashboard` matches 34px mobile header controls; default `trades` toolbar sizing. */
  size?: "trades" | "dashboard"
}

export function PerformanceShareIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      className="h-4 w-4 text-blue-300"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M4 12v7a1 1 0 001 1h14a1 1 0 001-1v-7M16 6l-4-4m0 0L8 6m4-4v12"
      />
    </svg>
  )
}

/** Performance share control used on /trades and dashboard filter bars. */
export default function PerformanceShareButton({
  onClick,
  className,
  size = "trades",
}: PerformanceShareButtonProps) {
  const mobileClass =
    size === "dashboard"
      ? "inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-md bg-white/10 transition hover:bg-white/20"
      : "order-3 flex h-10 w-10 items-center justify-center rounded bg-white/10 hover:bg-white/20"

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        mobileClass,
        "md:order-2 md:h-[34px] md:w-auto md:rounded-md md:px-3 md:py-1 md:text-sm md:text-white",
        className
      )}
      title="Share performance"
      aria-label="Share performance"
    >
      <PerformanceShareIcon />
    </button>
  )
}
