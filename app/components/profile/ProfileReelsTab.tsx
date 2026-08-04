"use client"

import EmptyState from "@/app/components/ui/EmptyState"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
import ProfileReelCard from "./ProfileReelCard"
import type { ReelRow } from "@/lib/reels"
import { memo } from "react"

type ProfileReelsTabProps = {
  ready: boolean
  reels: ReelRow[]
  isOwnProfile: boolean
  canView: boolean
  onCreateReel: () => void
  onOpenReel: (reel: ReelRow) => void
}

function ProfileReelsTab({
  ready,
  reels,
  isOwnProfile,
  canView,
  onCreateReel,
  onOpenReel,
}: ProfileReelsTabProps) {
  return (
    <div className="mt-1 w-full pb-8 sm:mt-4">
      {!ready ? (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 sm:gap-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <div
              key={i}
              className="aspect-[9/16] animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : reels.length === 0 ? (
        isOwnProfile ? (
          <EmptyState
            title="No Clips Yet"
            description="Share short vertical videos with your followers."
            action={
              <button
                type="button"
                onClick={onCreateReel}
                className="text-sm font-medium text-blue-300 hover:text-blue-200"
              >
                Create Clip →
              </button>
            }
            className="py-10"
          />
        ) : !canView ? (
          <ProfilePrivateTabMessage variant="reels" />
        ) : (
          <p className="text-center text-sm text-gray-400">No clips yet.</p>
        )
      ) : (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 sm:gap-4">
          {reels.map((reel) => (
            <ProfileReelCard
              key={reel.id}
              reel={reel}
              onOpen={() => onOpenReel(reel)}
            />
          ))}
        </div>
      )}
    </div>
  )
}

export default memo(ProfileReelsTab)
