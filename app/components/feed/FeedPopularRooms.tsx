"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import Skeleton from "@/app/components/ui/Skeleton"
import { isNativeIos } from "@/lib/nativePlatform"
import {
  fetchPopularTradeRooms,
  resolveRoomAvatarUrl,
  roomDisplayInitials,
  type PopularTradeRoom,
} from "@/lib/popularTradeRooms"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"
import { supabase } from "@/lib/supabaseClient"

const FEED_POPULAR_ROOMS_LIMIT = 4

function roomHref(room: PopularTradeRoom): string {
  const key = room.slug?.trim() || room.id
  return `/community?room=${encodeURIComponent(key)}`
}

function RoomAvatar({ room }: { room: PopularTradeRoom }) {
  const [imageFailed, setImageFailed] = useState(false)
  const avatarSrc = resolveRoomAvatarUrl(room)

  if (avatarSrc && !imageFailed) {
    return (
      <img
        src={avatarSrc}
        alt=""
        loading="lazy"
        decoding="async"
        className="h-9 w-9 shrink-0 rounded-full border border-white/10 object-cover"
        onError={() => setImageFailed(true)}
      />
    )
  }

  return (
    <div
      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/10 text-[10px] font-semibold text-gray-200"
      aria-hidden
    >
      {roomDisplayInitials(room.name)}
    </div>
  )
}

export default function FeedPopularRooms() {
  const [rooms, setRooms] = useState<PopularTradeRoom[] | null>(null)

  useEffect(() => {
    let cancelled = false
    let started = false
    const desktop = window.matchMedia("(min-width: 1280px)")

    const load = () => {
      if (cancelled || started || isNativeIos() || !desktop.matches) return
      started = true
      scheduleDeferredWork(() => {
        if (cancelled) return
        void fetchPopularTradeRooms(supabase, FEED_POPULAR_ROOMS_LIMIT).then(
          (result) => {
            if (cancelled) return
            setRooms(result.slice(0, FEED_POPULAR_ROOMS_LIMIT))
          }
        )
      })
    }

    load()
    desktop.addEventListener("change", load)
    return () => {
      cancelled = true
      desktop.removeEventListener("change", load)
    }
  }, [])

  if (rooms && rooms.length === 0) return null

  return (
    <section
      aria-label="Popular Trade Rooms"
      className="rounded-xl border border-white/10 bg-white/5 p-3"
    >
      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold text-white">
          Popular Trade Rooms
        </h2>
        <Link
          href="/community"
          prefetch={false}
          className="shrink-0 text-xs font-medium text-blue-300 hover:text-blue-200"
        >
          See All
        </Link>
      </div>

      {rooms == null ? (
        <div className="space-y-3" aria-hidden="true">
          {Array.from({ length: FEED_POPULAR_ROOMS_LIMIT }, (_, index) => (
            <div key={index} className="flex items-center gap-2.5">
              <Skeleton className="h-9 w-9 shrink-0 rounded-full" />
              <div className="min-w-0 flex-1 space-y-1.5">
                <Skeleton className="h-3 w-28" />
                <Skeleton className="h-2.5 w-16" />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <ul className="space-y-3">
          {rooms.map((room) => (
            <li key={room.id}>
              <Link
                href={roomHref(room)}
                prefetch={false}
                className="flex min-w-0 items-center gap-2.5 rounded-lg transition hover:bg-white/5"
              >
                <RoomAvatar room={room} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-semibold text-white">
                    {room.name}
                  </span>
                  <span className="block truncate text-xs text-gray-400">
                    {room.memberCount.toLocaleString()} member
                    {room.memberCount === 1 ? "" : "s"}
                  </span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
