"use client"

import CreateTradeRoomSection from "@/app/components/CreateTradeRoomSection"
import PopularTradeRoomsPanel from "@/app/components/dashboard/PopularTradeRoomsPanel"
import type { PopularTradeRoom } from "@/lib/popularTradeRooms"

type TradeRoomsDiscoverViewProps = {
  showCreateSection: boolean
  showExploreSection: boolean
  creatingRoom: boolean
  onCreateRoom: () => void
  memberRoomIds: ReadonlySet<string>
  onJoined: (room: PopularTradeRoom) => void
  exploreHeading?: string
  exploreSubheading?: string
}

export default function TradeRoomsDiscoverView({
  showCreateSection,
  showExploreSection,
  creatingRoom,
  onCreateRoom,
  memberRoomIds,
  onJoined,
  exploreHeading = "Explore More Trade Rooms",
  exploreSubheading = "Discover public Trade Rooms and join other trading communities.",
}: TradeRoomsDiscoverViewProps) {
  return (
    <div
      id="trade-rooms-discover"
      data-tt-trade-rooms-discover
      className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 py-6 md:px-8 md:py-10"
    >
      <div
        data-tt-trade-rooms-discover-inner
        className="mx-auto w-full max-w-2xl space-y-8"
      >
        {showCreateSection ? (
          <CreateTradeRoomSection
            onCreate={onCreateRoom}
            creating={creatingRoom}
          />
        ) : null}

        {showExploreSection ? (
          <section
            data-tt-trade-rooms-explore
            className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
          >
            <PopularTradeRoomsPanel
              active
              heading={exploreHeading}
              subheading={exploreSubheading}
              listClassName="space-y-3"
              memberRoomIds={memberRoomIds}
              onJoined={onJoined}
            />
          </section>
        ) : null}
      </div>
    </div>
  )
}
