"use client"

type Props = {
  message: string | null
  className?: string
  onDismiss?: () => void
}

export default function TradeRoomLiveModerationErrorNote({
  message,
  className,
  onDismiss,
}: Props) {
  if (!message?.trim()) {
    return null
  }
  return (
    <div
      role="alert"
      className={`rounded-lg border border-red-400/40 bg-red-500/10 px-2.5 py-2 text-xs text-red-100 ${className ?? ""}`}
    >
      <div className="flex items-start justify-between gap-2">
        <p>{message}</p>
        {onDismiss ? (
          <button
            type="button"
            className="shrink-0 text-[10px] uppercase tracking-wide text-red-200/80 hover:text-red-50"
            onClick={onDismiss}
          >
            Dismiss
          </button>
        ) : null}
      </div>
    </div>
  )
}
