"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import { supabase } from "@/lib/supabaseClient"
import { joinTradeRoom } from "@/lib/joinTradeRoom"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  fetchPopularTradeRooms,
  resolveRoomAvatarUrl,
  roomDisplayInitials,
  searchPublicTradeRooms,
  type PopularTradeRoom,
} from "@/lib/popularTradeRooms"

export type PopularTradeRoomsPanelProps = {
  /** When true, loads and displays recommended rooms. */
  active: boolean
  onJoined?: (room: PopularTradeRoom) => void
  heading?: string
  subheading?: string
  className?: string
  listClassName?: string
}

const SEARCH_DEBOUNCE_MS = 300

function RoomAvatar({ room }: { room: PopularTradeRoom }) {
  const [imageFailed, setImageFailed] = useState(false)
  const avatarSrc = resolveRoomAvatarUrl(room)
  const initials = roomDisplayInitials(room.name)

  if (avatarSrc && !imageFailed) {
    return (
      <img
        src={avatarSrc}
        alt=""
        loading="lazy"
        decoding="async"
        className="h-10 w-10 shrink-0 rounded-full object-cover"
        onError={() => setImageFailed(true)}
      />
    )
  }

  return (
    <div
      className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-semibold text-gray-200"
      aria-hidden
    >
      {initials}
    </div>
  )
}

function RoomListItem({
  room,
  joiningId,
  onJoin,
}: {
  room: PopularTradeRoom
  joiningId: string | null
  onJoin: (room: PopularTradeRoom) => void
}) {
  return (
    <li className="flex flex-col gap-3 rounded-lg border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex min-w-0 flex-1 gap-3">
        <RoomAvatar room={room} />
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-white">{room.name}</p>
          <p className="mt-1 text-xs text-gray-400">
            {room.memberCount.toLocaleString()} member
            {room.memberCount === 1 ? "" : "s"}
          </p>
          {room.description ? (
            <p className="mt-2 line-clamp-2 text-sm text-gray-300">
              {room.description}
            </p>
          ) : null}
        </div>
      </div>
      <button
        type="button"
        onClick={() => onJoin(room)}
        disabled={joiningId === room.id}
        className="shrink-0 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600 disabled:opacity-60"
      >
        {joiningId === room.id ? "Joining…" : "Join"}
      </button>
    </li>
  )
}

export default function PopularTradeRoomsPanel({
  active,
  onJoined,
  heading,
  subheading,
  className = "",
  listClassName = "max-h-[min(60vh,24rem)] space-y-3 overflow-y-auto pr-1",
}: PopularTradeRoomsPanelProps) {
  const [popularRooms, setPopularRooms] = useState<PopularTradeRoom[]>([])
  const [searchResults, setSearchResults] = useState<PopularTradeRoom[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [debouncedSearch, setDebouncedSearch] = useState("")
  const [loadingPopular, setLoadingPopular] = useState(false)
  const [searching, setSearching] = useState(false)
  const [joiningId, setJoiningId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const isSearchActive = debouncedSearch.trim().length > 0

  const displayRooms = useMemo(
    () => (isSearchActive ? searchResults : popularRooms),
    [isSearchActive, popularRooms, searchResults]
  )

  useEffect(() => {
    if (!active) {
      setSearchQuery("")
      setDebouncedSearch("")
      setSearchResults([])
      return
    }

    const timer = window.setTimeout(() => {
      setDebouncedSearch(searchQuery)
    }, SEARCH_DEBOUNCE_MS)

    return () => window.clearTimeout(timer)
  }, [active, searchQuery])

  useEffect(() => {
    if (!active) return

    let cancelled = false
    setLoadingPopular(true)
    setError(null)

    void (async () => {
      const list = await fetchPopularTradeRooms(supabase)
      if (cancelled) return
      setPopularRooms(list)
      setLoadingPopular(false)
    })()

    return () => {
      cancelled = true
    }
  }, [active])

  useEffect(() => {
    if (!active) return

    const query = debouncedSearch.trim()
    if (!query) {
      setSearchResults([])
      setSearching(false)
      return
    }

    let cancelled = false
    setSearching(true)
    setError(null)

    void (async () => {
      const list = await searchPublicTradeRooms(supabase, query)
      if (cancelled) return
      setSearchResults(list)
      setSearching(false)
    })()

    return () => {
      cancelled = true
    }
  }, [active, debouncedSearch])

  const handleJoin = useCallback(
    async (room: PopularTradeRoom) => {
      if (isDemoSupabaseBlocked()) {
        requestDemoSignup("room")
        return
      }

      setJoiningId(room.id)
      setError(null)

      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user?.id) {
        setError("Sign in to join a room.")
        setJoiningId(null)
        return
      }

      const result = await joinTradeRoom(supabase, room.id, user.id)
      setJoiningId(null)

      if (!result.ok) {
        setError(result.error)
        return
      }

      onJoined?.(room)
    },
    [onJoined]
  )

  const listLoading = isSearchActive ? searching : loadingPopular

  if (!active) return null

  return (
    <div className={className}>
      {heading ? (
        <h2 className="text-xl font-semibold text-white md:text-2xl">{heading}</h2>
      ) : null}
      {subheading ? (
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-gray-300 md:text-base">
          {subheading}
        </p>
      ) : null}

      <label className={`block ${heading || subheading ? "mt-6" : ""}`}>
        <span className="sr-only">Search Trade Rooms</span>
        <input
          type="search"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search Trade Rooms..."
          className="w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500 focus:border-blue-400/50 focus:outline-none focus:ring-1 focus:ring-blue-400/40"
          autoComplete="off"
        />
      </label>

      {listLoading ? (
        <p className="mt-4 text-sm text-gray-400">
          {isSearchActive ? "Searching rooms…" : "Loading rooms…"}
        </p>
      ) : displayRooms.length === 0 ? (
        <EmptyState
          title={isSearchActive ? "No matching rooms" : "No rooms available"}
          description={
            isSearchActive
              ? "Try another name or clear search to see popular rooms again."
              : "Check back soon or browse trade rooms from a trader profile."
          }
          className="py-6"
        />
      ) : (
        <ul className={`mt-4 ${listClassName}`}>
          {displayRooms.map((room) => (
            <RoomListItem
              key={room.id}
              room={room}
              joiningId={joiningId}
              onJoin={(next) => void handleJoin(next)}
            />
          ))}
        </ul>
      )}
      {error ? (
        <p className="mt-3 text-sm text-red-400" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  )
}
