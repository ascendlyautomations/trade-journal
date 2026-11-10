"use client"

import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import CreateFirstTradeRoomCard from "@/app/components/CreateFirstTradeRoomCard"
import ExploreMoreTradeRoomsCard from "@/app/components/ExploreMoreTradeRoomsCard"
import StorageImage from "@/app/components/ui/StorageImage"
import { resolveStoredRoomImageUrl } from "@/lib/storageOptimizedMedia"
import { MOBILE_WEB_NEUTRAL_PAGE_BG } from "@/lib/mobileWebPageSurface"

export type MobileWebTradeRoomsHomeRoom = {
  id: string
  name?: string | null
  slug?: string | null
  image_url?: string | null
  avatar_url?: string | null
  is_private?: boolean | null
  owner_user_id?: string | null
}

type MobileWebTradeRoomsHomeProps = {
  rooms: MobileWebTradeRoomsHomeRoom[]
  loading: boolean
  loadError: string | null
  searchQuery: string
  onSearchChange: (value: string) => void
  userId: string | null
  showCreateFirstRoomCard: boolean
  needsJoin: boolean
  onSelectRoom: (room: MobileWebTradeRoomsHomeRoom) => void
  onRetryLoad: () => void
  onExploreCreate: () => void
  onRefresh: () => Promise<void>
}

function roomAvatarSrc(room: MobileWebTradeRoomsHomeRoom): string {
  const resolved = [room.image_url, room.avatar_url]
    .map((v) =>
      v != null && String(v).trim() !== ""
        ? resolveStoredRoomImageUrl(String(v).trim())
        : null
    )
    .find((value): value is string => Boolean(value))
  return resolved || "/default-avatar.png"
}

export default function MobileWebTradeRoomsHome({
  rooms,
  loading,
  loadError,
  searchQuery,
  onSearchChange,
  userId,
  showCreateFirstRoomCard,
  needsJoin,
  onSelectRoom,
  onRetryLoad,
  onExploreCreate,
  onRefresh,
}: MobileWebTradeRoomsHomeProps) {
  return (
    <div
      className={`flex min-h-0 flex-1 flex-col ${MOBILE_WEB_NEUTRAL_PAGE_BG}`}
      data-tt-mobile-trade-rooms-home
    >
      <div className="shrink-0 border-b border-white/10 px-3 pb-2 pt-1">
        <h1 className="sr-only">Trade Rooms</h1>
        <p className="px-1 pb-2 text-[17px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
          Trade Rooms
        </p>
        <input
          type="search"
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Search rooms"
          aria-label="Search rooms"
          className="h-11 w-full rounded-[10px] border border-white/10 bg-white/5 px-3 text-sm text-white placeholder:text-white/40"
        />
      </div>

      <NativeIosPullToRefresh
        className="min-h-0 flex-1 overflow-y-auto px-2 py-2"
        onRefresh={onRefresh}
      >
        {loading ? (
          <div className="space-y-2 px-1">
            {Array.from({ length: 6 }).map((_, i) => (
              <div
                key={i}
                className="flex min-h-[72px] items-center gap-3 rounded-[14px] bg-white/[0.04] px-3 py-3"
              >
                <div className="h-[52px] w-[52px] shrink-0 animate-pulse rounded-full bg-white/10" />
                <div className="h-4 flex-1 max-w-[160px] animate-pulse rounded bg-white/10" />
              </div>
            ))}
          </div>
        ) : loadError && rooms.length === 0 ? (
          <div className="space-y-2 px-2 py-4">
            <p className="text-sm text-red-300/90">{loadError}</p>
            <button
              type="button"
              className="text-sm font-medium text-[#4EC4E0]"
              onClick={onRetryLoad}
            >
              Retry
            </button>
          </div>
        ) : rooms.length === 0 && !showCreateFirstRoomCard ? (
          <p className="px-2 py-6 text-center text-sm text-[color:var(--tt-text-muted,#57606a)]">
            No rooms found.
          </p>
        ) : (
          <div className="space-y-1">
            {loadError && rooms.length > 0 ? (
              <div className="mb-2 rounded-lg border border-amber-500/25 bg-amber-500/10 px-2 py-1.5 text-xs text-amber-100/90">
                {loadError}
              </div>
            ) : null}
            {showCreateFirstRoomCard ? (
              <CreateFirstTradeRoomCard className="mb-2" onClick={onExploreCreate} />
            ) : null}
            {rooms.map((room) => {
              const isOwnRoom = Boolean(userId && room.owner_user_id === userId)
              return (
                <button
                  key={room.id}
                  type="button"
                  onClick={() => onSelectRoom(room)}
                  className="mb-1 flex min-h-[72px] w-full items-center gap-3 rounded-[14px] bg-white/[0.04] px-3 py-3 text-left transition active:bg-white/10"
                >
                  <StorageImage
                    src={roomAvatarSrc(room)}
                    preset="room-list-thumb"
                    fallbackToOriginal={false}
                    alt=""
                    intrinsicWidth={52}
                    intrinsicHeight={52}
                    className="h-[52px] w-[52px] shrink-0 rounded-full object-cover"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[16px] font-semibold text-[color:var(--tt-text,#f0f3f6)]">
                      {room.name}
                    </p>
                    <p className="mt-0.5 truncate text-[13px] text-[color:var(--tt-text-muted,#57606a)]">
                      {room.is_private ? "Private" : "Public"}
                      {isOwnRoom ? " · Owner" : ""}
                    </p>
                  </div>
                </button>
              )
            })}
            {!loading && !needsJoin ? (
              <ExploreMoreTradeRoomsCard
                onClick={onExploreCreate}
                selected={false}
                className="mb-1"
              />
            ) : null}
          </div>
        )}
      </NativeIosPullToRefresh>
    </div>
  )
}
