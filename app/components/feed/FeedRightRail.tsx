"use client"

import FeedPopularRooms from "@/app/components/feed/FeedPopularRooms"
import FeedSuggestedTraders from "@/app/components/feed/FeedSuggestedTraders"

type FeedRightRailProps = {
  viewerId: string
  followingIds: readonly string[]
  onFollowingChange: (targetUserId: string, following: boolean) => void
}

export default function FeedRightRail({
  viewerId,
  followingIds,
  onFollowingChange,
}: FeedRightRailProps) {
  return (
    <aside data-tt-feed-rail className="hidden w-[280px] shrink-0">
      <FeedSuggestedTraders
        viewerId={viewerId}
        followingIds={followingIds}
        onFollowingChange={onFollowingChange}
      />
      <FeedPopularRooms />
    </aside>
  )
}
