"use client"

import { memo } from "react"
import ReelClipPlayOverlay from "@/app/components/ReelClipPlayOverlay"
import ReelVideoPosterFrame from "@/app/components/ReelVideoPosterFrame"
import { formatReelDuration, type ReelRow } from "@/lib/reels"

export type ReelThumbnailPreviewProps = {
  reel: Pick<ReelRow, "thumbnail_url" | "video_url" | "duration_seconds">
  onClick?: () => void
  className?: string
  priority?: boolean
  /** Defaults to max-w-[280px] — use a smaller width on compact trade cards. */
  maxWidthClass?: string
}

function ReelThumbnailPreview({
  reel,
  onClick,
  className = "",
  maxWidthClass = "max-w-[280px]",
  priority = false,
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
      aria-label={interactive ? "Watch linked clip" : undefined}
    >
      <ReelVideoPosterFrame
        thumbnailUrl={reel.thumbnail_url}
        videoUrl={reel.video_url}
        priority={priority}
        className="aspect-[9/16] w-full object-cover"
      />
      <ReelClipPlayOverlay />
      {reel.duration_seconds != null ? (
        <span className="pointer-events-none absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-white">
          {formatReelDuration(Number(reel.duration_seconds))}
        </span>
      ) : null}
    </button>
  )
}

export default memo(ReelThumbnailPreview)
