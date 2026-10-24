"use client"

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import { supabase } from "@/lib/supabaseClient"
import { joinTradeRoom } from "@/lib/joinTradeRoom"
import {
  EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE,
  fetchExploreSuggestedTradeRooms,
} from "@/lib/exploreCommunityTradeRooms"
import {
  resolveRoomAvatarUrl,
  roomDisplayInitials,
  type PopularTradeRoom,
} from "@/lib/popularTradeRooms"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { tradeRoomSharePath } from "@/lib/tradeRoomShareUrl"

const PANEL_CLASS =
  "rounded-xl border border-white/10 bg-white/5 p-2.5 backdrop-blur-md md:p-4"

function roomHref(room: PopularTradeRoom): string {
  const key = room.slug?.trim() || room.id
  return tradeRoomSharePath(key)
}

function RoomAvatar({ room }: { room: PopularTradeRoom }) {
  const [failed, setFailed] = useState(false)
  const src = resolveRoomAvatarUrl(room)
  const initials = roomDisplayInitials(room.name)

  if (src && !failed) {
    return (
      <img
        src={src}
        alt=""
        loading="lazy"
        decoding="async"
        className="h-12 w-12 shrink-0 rounded-xl object-cover"
        onError={() => setFailed(true)}
      />
    )
  }

  return (
    <div
      className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/10 text-sm font-semibold text-gray-200"
      aria-hidden
    >
      {initials}
    </div>
  )
}

type Props = {
  memberRoomIds: ReadonlySet<string>
}

export default function ExploreSuggestedRoomsSection({ memberRoomIds }: Props) {
  const { user } = useUserProfile()
  const [allRooms, setAllRooms] = useState<PopularTradeRoom[]>([])
  const [visibleCount, setVisibleCount] = useState(
    EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE
  )
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [joiningId, setJoiningId] = useState<string | null>(null)

  const loadInitial = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await fetchExploreSuggestedTradeRooms(supabase)
      if (result.status === "rpc_error") {
        setError("Couldn't load Trade Rooms. Please try again.")
        setAllRooms([])
        setVisibleCount(EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE)
        return
      }
      setAllRooms(result.rooms)
      setVisibleCount(EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE)
    } catch (e) {
      console.error("[explore] suggested rooms:", e)
      setError("Couldn't load Trade Rooms. Please try again.")
      setAllRooms([])
      setVisibleCount(EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadInitial()
  }, [loadInitial])

  const eligibleRooms = useMemo(
    () => allRooms.filter((room) => !memberRoomIds.has(room.id)),
    [allRooms, memberRoomIds]
  )

  const visibleRooms = useMemo(
    () => eligibleRooms.slice(0, visibleCount),
    [eligibleRooms, visibleCount]
  )

  const showLoadMore = visibleCount < eligibleRooms.length

  async function handleJoin(room: PopularTradeRoom) {
    if (isDemoSupabaseBlocked()) {
      requestDemoSignup("room")
      return
    }
    if (!user?.id) return

    setJoiningId(room.id)
    const result = await joinTradeRoom(supabase, room.id, user.id)
    setJoiningId(null)
    if (!result.ok) {
      setError(result.error)
      return
    }
    setAllRooms((prev) => prev.filter((entry) => entry.id !== room.id))
  }

  return (
    <section className={PANEL_CLASS} aria-labelledby="explore-suggested-rooms-heading">
      <div className="mb-3">
        <h2
          id="explore-suggested-rooms-heading"
          className="text-sm font-semibold text-white md:text-base"
        >
          Suggested Trade Rooms
        </h2>
        <p className="mt-0.5 text-xs text-gray-400">
          Public rooms to explore
        </p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE }).map((_, i) => (
            <div
              key={i}
              className="h-36 animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : error && visibleRooms.length === 0 ? (
        <EmptyState
          title="Couldn't load Trade Rooms"
          description={error}
          className="py-6"
          action={
            <button
              type="button"
              onClick={() => void loadInitial()}
              className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
            >
              Retry
            </button>
          }
        />
      ) : visibleRooms.length === 0 ? (
        <EmptyState
          title="No suggested rooms"
          description="Public Trade Rooms will appear here as the community grows."
          className="py-6"
        />
      ) : (
        <>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {visibleRooms.map((room) => (
              <article
                key={room.id}
                className="flex h-full flex-col rounded-xl border border-white/10 bg-black/20 p-3"
              >
                <div className="flex gap-3">
                  <RoomAvatar room={room} />
                  <div className="min-w-0 flex-1">
                    <Link
                      href={roomHref(room)}
                      className="line-clamp-2 font-semibold text-white hover:text-blue-200"
                    >
                      {room.name}
                    </Link>
                    <p className="mt-1 text-xs text-gray-400">
                      {room.memberCount.toLocaleString()} active member
                      {room.memberCount === 1 ? "" : "s"}
                    </p>
                  </div>
                </div>
                {room.description ? (
                  <p className="mt-2 line-clamp-2 flex-1 text-sm text-gray-300">
                    {room.description}
                  </p>
                ) : (
                  <div className="flex-1" />
                )}
                <div className="mt-3 flex gap-2">
                  <Link
                    href={roomHref(room)}
                    className="flex-1 rounded-lg border border-white/15 bg-white/5 px-3 py-2 text-center text-sm font-medium text-white transition hover:bg-white/10"
                  >
                    Open
                  </Link>
                  <button
                    type="button"
                    disabled={!user?.id || joiningId === room.id}
                    onClick={() => void handleJoin(room)}
                    className="flex-1 rounded-lg bg-blue-500 px-3 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {joiningId === room.id ? "Joining…" : "Join"}
                  </button>
                </div>
              </article>
            ))}
          </div>
          {showLoadMore ? (
            <div className="mt-4 flex justify-center">
              <button
                type="button"
                onClick={() =>
                  setVisibleCount(
                    (count) =>
                      count + EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE
                  )
                }
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
              >
                Load More
              </button>
            </div>
          ) : null}
        </>
      )}
      {error && visibleRooms.length > 0 ? (
        <p className="mt-2 text-xs text-red-400" role="alert">
          {error}
        </p>
      ) : null}
    </section>
  )
}
