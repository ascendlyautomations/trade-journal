"use client"

type ReelClipPlayOverlayProps = {
  className?: string
  buttonClassName?: string
  dimClassName?: string
}

export default function ReelClipPlayOverlay({
  className = "",
  buttonClassName = "h-12 w-12 text-lg",
  dimClassName = "bg-black/20",
}: ReelClipPlayOverlayProps) {
  return (
    <div
      className={`pointer-events-none absolute inset-0 flex items-center justify-center ${dimClassName} ${className}`}
      aria-hidden
    >
      <span
        className={`flex items-center justify-center rounded-full border border-white/20 bg-black/50 text-white backdrop-blur-sm ${buttonClassName}`}
      >
        ▶
      </span>
    </div>
  )
}
