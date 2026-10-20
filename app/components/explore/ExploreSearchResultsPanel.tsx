"use client"

import Link from "next/link"
import { useState } from "react"
import FollowButton from "@/app/components/FollowButton"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import type { PopularTradeRoom } from "@/lib/popularTradeRooms"
import {
  resolveRoomAvatarUrl,
  roomDisplayInitials,
} from "@/lib/popularTradeRooms"
import { profilePath } from "@/lib/profileRoutes"

export type ExploreSearchProfileResult = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
  is_private?: boolean | null
}

type ExploreSearchResultsPanelProps = {
  profiles: ExploreSearchProfileResult[]
  rooms: PopularTradeRoom[]
  currentUserId: string | null
  followingIds: Set<string>
  requestedIds: Set<string>
  followsYouIds: Set<string>
  memberRoomIds: ReadonlySet<string>
  onFollowingChange: (userId: string, following: boolean) => void
  onRequestedChange: (userId: string, requested: boolean) => void
  onJoinRoom: (room: PopularTradeRoom) => Promise<void>
}

function roomHref(room: PopularTradeRoom): string {
  const key = room.slug?.trim() || room.id
  return `/trade-rooms?room=${encodeURIComponent(key)}`
}

function SearchRoomAvatar({ room }: { room: PopularTradeRoom }) {
  const [failed, setFailed] = useState(false)
  const src = resolveRoomAvatarUrl(room)
  const initials = roomDisplayInitials(room.name)

  if (src && !failed) {
    return (
      <img
        src={src}
        alt=""
        className="h-10 w-10 shrink-0 rounded-xl object-cover border border-white/10"
        onError={() => setFailed(true)}
      />
    )
  }

  return (
    <div
      className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-white/10 bg-white/10 text-xs font-semibold text-gray-200"
      aria-hidden
    >
      {initials}
    </div>
  )
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="border-b border-white/10 bg-white/[0.03] px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-gray-400">
      {children}
    </p>
  )
}

export default function ExploreSearchResultsPanel({
  profiles,
  rooms,
  currentUserId,
  followingIds,
  requestedIds,
  followsYouIds,
  memberRoomIds,
  onFollowingChange,
  onRequestedChange,
  onJoinRoom,
}: ExploreSearchResultsPanelProps) {
  const [joiningRoomId, setJoiningRoomId] = useState<string | null>(null)

  return (
    <div className="absolute left-0 right-0 z-[100] mt-2 max-h-[min(70vh,28rem)] overflow-y-auto overscroll-contain rounded-xl border border-white/10 bg-[#0f172a] shadow-xl">
      {profiles.length > 0 ? (
        <div>
          <SectionLabel>People</SectionLabel>
          {profiles.map((result) => (
            <div
              key={result.id}
              className="flex items-center justify-between gap-3 border-b border-white/5 px-3 py-2.5 last:border-b-0 hover:bg-white/5"
            >
              <Link
                href={profilePath({
                  id: result.id,
                  username: result.username,
                })}
                className="flex min-w-0 items-center gap-3"
              >
                <ProfileAvatarImg
                  src={result.avatar_url}
                  className="h-10 w-10 shrink-0 border border-white/10"
                />
                <div className="min-w-0">
                  <p className="truncate font-semibold text-white">
                    {result.name?.trim() || result.username}
                  </p>
                  {result.username ? (
                    <p className="truncate text-xs text-gray-300">
                      @{result.username}
                    </p>
                  ) : null}
                </div>
              </Link>
              <FollowButton
                targetUserId={result.id}
                currentUserId={currentUserId}
                targetIsPrivate={result.is_private}
                followingIds={followingIds}
                requestedIds={requestedIds}
                followsYouIds={followsYouIds}
                onFollowingChange={onFollowingChange}
                onRequestedChange={onRequestedChange}
              />
            </div>
          ))}
        </div>
      ) : null}

      {rooms.length > 0 ? (
        <div>
          <SectionLabel>Trade Rooms</SectionLabel>
          {rooms.map((room) => {
            const isMember = memberRoomIds.has(room.id)
            return (
              <div
                key={room.id}
                className="flex items-center justify-between gap-3 border-b border-white/5 px-3 py-2.5 last:border-b-0 hover:bg-white/5"
              >
                <Link
                  href={roomHref(room)}
                  className="flex min-w-0 flex-1 items-center gap-3"
                >
                  <SearchRoomAvatar room={room} />
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-white">
                      {room.name}
                    </p>
                    {room.slug ? (
                      <p className="truncate text-xs text-gray-300">
                        {room.slug}
                      </p>
                    ) : (
                      <p className="truncate text-xs text-gray-400">
                        {room.memberCount.toLocaleString()} member
                        {room.memberCount === 1 ? "" : "s"}
                      </p>
                    )}
                  </div>
                </Link>
                {isMember ? (
                  <Link
                    href={roomHref(room)}
                    className="shrink-0 rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-white/10"
                  >
                    Open
                  </Link>
                ) : (
                  <button
                    type="button"
                    disabled={!currentUserId || joiningRoomId === room.id}
                    onClick={() => {
                      setJoiningRoomId(room.id)
                      void onJoinRoom(room).finally(() => setJoiningRoomId(null))
                    }}
                    className="shrink-0 rounded-lg bg-blue-500 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {joiningRoomId === room.id ? "Joining…" : "Join"}
                  </button>
                )}
              </div>
            )
          })}
        </div>
      ) : null}
    </div>
  )
}
