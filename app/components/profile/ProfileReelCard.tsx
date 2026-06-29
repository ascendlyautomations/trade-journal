"use client"

import type { ReelRow } from "@/lib/reels"
import { formatRelativeTime } from "@/lib/formatRelativeTime"

type ProfileReelCardProps = {
  reel: ReelRow
  creator?: {
    username?: string | null
    avatar_url?: string | null
    name?: string | null
  } | null
  onOpen: () => void
}

export default function ProfileReelCard({
  reel,
  creator,
  onOpen,
}: ProfileReelCardProps) {
  const displayName =
    creator?.username?.trim() ||
    creator?.name?.trim() ||
    "Trader"

  return (
    <button
      type="button"
      onClick={onOpen}
      className="group w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 text-left transition hover:border-emerald-400/30 hover:bg-white/[0.07]"
    >
      <div className="relative aspect-[9/16] w-full overflow-hidden bg-black/40">
        <img
          src={reel.thumbnail_url}
          alt=""
          loading="lazy"
          className="h-full w-full object-cover transition duration-300 group-hover:scale-[1.02]"
        />
        <div className="absolute inset-0 flex items-center justify-center bg-black/20 opacity-0 transition group-hover:opacity-100">
          <span className="flex h-11 w-11 items-center justify-center rounded-full border border-white/20 bg-black/50 text-white backdrop-blur-sm">
            ▶
          </span>
        </div>
        {reel.duration_seconds != null ? (
          <span className="absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-white">
            {formatReelDuration(reel.duration_seconds)}
          </span>
        ) : null}
      </div>

      <div className="space-y-2 p-3">
        {reel.caption?.trim() ? (
          <p className="line-clamp-2 text-sm text-gray-100">{reel.caption}</p>
        ) : (
          <p className="text-sm italic text-gray-500">No caption</p>
        )}

        <div className="flex items-center gap-2">
          <img
            src={creator?.avatar_url || "/default-avatar.png"}
            alt=""
            className="h-6 w-6 rounded-full border border-white/10 object-cover"
            loading="lazy"
          />
          <div className="min-w-0">
            <p className="truncate text-xs font-medium text-gray-200">
              {displayName}
            </p>
            <p className="text-[11px] text-gray-500">
              {formatRelativeTime(reel.created_at)}
            </p>
          </div>
        </div>
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
