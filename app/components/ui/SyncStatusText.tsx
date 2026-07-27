"use client"

import InlineMicroSpinner from "@/app/components/ui/InlineMicroSpinner"
import { MICRO } from "@/lib/microInteractions"

type SyncStatusTextProps = {
  status: "idle" | "sending" | "sent" | "failed" | "posting" | "syncing"
  onRetry?: () => void
  className?: string
  align?: "left" | "right"
  /** Comment failures use “Failed to post”; messages keep “Failed · Tap to retry”. */
  kind?: "message" | "comment"
}

/**
 * Lightweight status line for optimistic messages / comments.
 * Prefer this over full-screen errors or giant spinners.
 */
export default function SyncStatusText({
  status,
  onRetry,
  className = "",
  align = "right",
  kind = "message",
}: SyncStatusTextProps) {
  if (status === "idle" || status === "sent") return null

  const alignClass = align === "right" ? "text-right" : "text-left"

  if (status === "failed") {
    return (
      <button
        type="button"
        onClick={onRetry}
        className={`${MICRO.statusFailed} ${alignClass} mt-0.5 text-[11px] underline decoration-red-400/60 underline-offset-2 ${className}`.trim()}
      >
        {kind === "comment" ? "Failed to post · Retry" : "Failed · Tap to retry"}
      </button>
    )
  }

  const label =
    status === "posting"
      ? "Posting…"
      : status === "syncing"
        ? "Saving…"
        : "Sending…"

  return (
    <p
      className={`${MICRO.statusSending} ${alignClass} mt-0.5 inline-flex items-center gap-1 text-[11px] ${className}`.trim()}
    >
      <InlineMicroSpinner className="h-2.5 w-2.5 opacity-70" label={label} />
      <span>{label}</span>
    </p>
  )
}
