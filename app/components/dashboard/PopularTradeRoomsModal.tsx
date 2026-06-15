"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Modal from "@/app/components/ui/Modal"
import EmptyState from "@/app/components/ui/EmptyState"
import { supabase } from "@/lib/supabaseClient"
import { joinTradeRoom } from "@/lib/joinTradeRoom"
import {
  fetchPopularTradeRooms,
  type PopularTradeRoom,
} from "@/lib/popularTradeRooms"

export type PopularTradeRoomsModalProps = {
  open: boolean
  onClose: () => void
  onJoined?: () => void
}

export default function PopularTradeRoomsModal({
  open,
  onClose,
  onJoined,
}: PopularTradeRoomsModalProps) {
  const router = useRouter()
  const [rooms, setRooms] = useState<PopularTradeRoom[]>([])
  const [loading, setLoading] = useState(false)
  const [joiningId, setJoiningId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return

    let cancelled = false
    setLoading(true)
    setError(null)

    void (async () => {
      const list = await fetchPopularTradeRooms(supabase)
      if (cancelled) return
      setRooms(list)
      setLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [open])

  const handleJoin = useCallback(
    async (room: PopularTradeRoom) => {
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

      onJoined?.()
      onClose()

      const target = room.slug ?? room.id
      router.push(`/trade-rooms?room=${encodeURIComponent(String(target))}`)
    },
    [onClose, onJoined, router]
  )

  return (
    <Modal open={open} onClose={onClose} title="Popular Trade Rooms" size="lg">
      {loading ? (
        <p className="text-sm text-gray-400">Loading rooms…</p>
      ) : rooms.length === 0 ? (
        <EmptyState
          title="No rooms available"
          description="Check back soon or browse trade rooms from a trader profile."
          className="py-6"
        />
      ) : (
        <ul className="max-h-[min(60vh,24rem)] space-y-3 overflow-y-auto pr-1">
          {rooms.map((room) => (
            <li
              key={room.id}
              className="flex flex-col gap-3 rounded-lg border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-center sm:justify-between"
            >
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
              <button
                type="button"
                onClick={() => void handleJoin(room)}
                disabled={joiningId === room.id}
                className="shrink-0 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600 disabled:opacity-60"
              >
                {joiningId === room.id ? "Joining…" : "Join"}
              </button>
            </li>
          ))}
        </ul>
      )}
      {error ? (
        <p className="mt-3 text-sm text-red-400" role="alert">
          {error}
        </p>
      ) : null}
    </Modal>
  )
}
