"use client"

import { memo } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import { formatReelDuration, type ReelRow } from "@/lib/reels"

export type ReelThumbnailPreviewProps = {
  reel: Pick<ReelRow, "thumbnail_url" | "duration_seconds">
  onClick?: () => void
  className?: string
  /** Defaults to max-w-[280px] — use a smaller width on compact trade cards. */
  maxWidthClass?: string
}

function ReelThumbnailPreview({
  reel,
  onClick,
  className = "",
  maxWidthClass = "max-w-[280px]",
}: ReelThumbnailPreviewProps) {
  const interactive = onClick != null

  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation()
        onClick?.()
      }}
      disabled={!interactive}
      className={`relative mx-auto block w-full overflow-hidden rounded-xl border border-white/10 bg-black/40 ${maxWidthClass} ${
        interactive
          ? "cursor-pointer transition hover:border-violet-400/30 hover:bg-black/50"
          : "cursor-default"
      } ${className}`}
      aria-label={interactive ? "Watch linked reel" : undefined}
    >
      <StorageImage
        src={String(reel.thumbnail_url)}
        originalSrc={String(reel.thumbnail_url)}
        preset="reel-thumb"
        alt=""
        className="aspect-[9/16] w-full object-cover"
      />
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/20">
        <span className="flex h-12 w-12 items-center justify-center rounded-full border border-white/20 bg-black/50 text-lg text-white backdrop-blur-sm">
          ▶
        </span>
      </div>
      {reel.duration_seconds != null ? (
        <span className="pointer-events-none absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-white">
          {formatReelDuration(Number(reel.duration_seconds))}
        </span>
      ) : null}
    </button>
  )
}

export default memo(ReelThumbnailPreview)
