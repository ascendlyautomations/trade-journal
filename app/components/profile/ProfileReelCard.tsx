"use client"

import ReelClipPlayOverlay from "@/app/components/ReelClipPlayOverlay"
import ReelVideoPosterFrame from "@/app/components/ReelVideoPosterFrame"
import type { ReelRow } from "@/lib/reels"
import { resolveReelCaption } from "@/lib/reels"
import { formatRelativeTime } from "@/lib/formatRelativeTime"

type ProfileReelCardProps = {
  reel: ReelRow
  onOpen: () => void
}

export default function ProfileReelCard({ reel, onOpen }: ProfileReelCardProps) {
  const caption = resolveReelCaption(reel)

  return (
    <button
      type="button"
      onClick={onOpen}
      className="group w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 text-left transition hover:border-emerald-400/30 hover:bg-white/[0.07]"
    >
      <div className="relative aspect-[9/16] w-full overflow-hidden bg-black/40">
        <ReelVideoPosterFrame
          thumbnailUrl={reel.thumbnail_url}
          videoUrl={reel.video_url}
          className="h-full w-full object-cover transition duration-300 group-hover:scale-[1.02]"
        />
        <div className="opacity-0 transition group-hover:opacity-100">
          <ReelClipPlayOverlay
            buttonClassName="h-11 w-11"
            dimClassName="bg-black/20"
          />
        </div>
        {reel.duration_seconds != null ? (
          <span className="absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-white">
            {formatReelDuration(reel.duration_seconds)}
          </span>
        ) : null}
      </div>

      <div className="space-y-1.5 p-3">
        {caption ? (
          <p className="line-clamp-2 text-sm text-gray-100">{caption}</p>
        ) : (
          <p className="text-sm italic text-gray-500">No caption</p>
        )}
        <p className="text-[11px] text-gray-500">
          {formatRelativeTime(reel.created_at)}
        </p>
      </div>
    </button>
  )
}

function formatReelDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds))
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${String(secs).padStart(2, "0")}`
}
