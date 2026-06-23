"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { joinTradeRoom } from "@/lib/joinTradeRoom"
import {
  formatRoomMemberCount,
  isRoomSharePost,
  resolveRoomShareLogo,
  type RoomSharePostFields,
} from "@/lib/roomSharePost"
import { supabase } from "@/lib/supabaseClient"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { useFeedbackPopup } from "@/app/components/ui"

type FeedRoomShareCardProps = {
  post: RoomSharePostFields
  viewerUserId?: string | null
  className?: string
}

export default function FeedRoomShareCard({
  post,
  viewerUserId,
  className = "",
}: FeedRoomShareCardProps) {
  const router = useRouter()
  const { showPopup } = useFeedbackPopup()
  const [memberCount, setMemberCount] = useState<number | null>(null)
  const [isMember, setIsMember] = useState(false)
  const [actionBusy, setActionBusy] = useState(false)

  const roomId = post.room_id != null ? String(post.room_id).trim() : ""
  const roomName =
    post.room_name != null && String(post.room_name).trim() !== ""
      ? String(post.room_name).trim()
      : "Trade Room"
  const roomDescription =
    post.room_description != null
      ? String(post.room_description).trim()
      : ""
  const logoSrc = resolveRoomShareLogo(post.room_logo)

  useEffect(() => {
    if (!roomId) return

    let cancelled = false

    void (async () => {
      const [{ count }, membership] = await Promise.all([
        supabase
          .from("room_members")
          .select("*", { count: "exact", head: true })
          .eq("room_id", roomId)
          .is("left_at", null),
        viewerUserId
          ? supabase
              .from("room_members")
              .select("left_at")
              .eq("room_id", roomId)
              .eq("user_id", viewerUserId)
              .maybeSingle()
          : Promise.resolve({ data: null }),
      ])

      if (cancelled) return
      setMemberCount(count ?? 0)
      setIsMember(
        membership.data != null && membership.data.left_at == null
      )
    })()

    return () => {
      cancelled = true
    }
  }, [roomId, viewerUserId])

  const openRoom = useCallback(
    async (joinedRoomId: string) => {
      const { data: room } = await supabase
        .from("rooms")
        .select("id, slug")
        .eq("id", joinedRoomId)
        .maybeSingle()

      const key =
        room?.slug != null && String(room.slug).trim() !== ""
          ? String(room.slug).trim()
          : room?.id != null
            ? String(room.id)
            : joinedRoomId

      router.push(`/trade-rooms?room=${encodeURIComponent(key)}`)
    },
    [router]
  )

  const handleAction = useCallback(
    async (event: React.MouseEvent) => {
      event.stopPropagation()

      if (!roomId || actionBusy) return

      if (isMember) {
        await openRoom(roomId)
        return
      }

      if (!viewerUserId) {
        router.push("/login")
        return
      }

      setActionBusy(true)
      try {
        const result = await joinTradeRoom(supabase, roomId, viewerUserId)
        if (!result.ok) {
          showPopup({
            type: "error",
            message: handleSupabaseError({ message: result.error }),
          })
          return
        }
        setIsMember(true)
        setMemberCount((prev) => (prev == null ? 1 : prev + (result.alreadyMember ? 0 : 1)))
        await openRoom(roomId)
      } finally {
        setActionBusy(false)
      }
    },
    [
      actionBusy,
      isMember,
      openRoom,
      roomId,
      router,
      showPopup,
      viewerUserId,
    ]
  )

  if (!isRoomSharePost(post)) return null

  return (
    <div
      className={`rounded-xl border border-white/10 bg-gradient-to-br from-[#0b1f3a]/90 to-[#0f172a]/90 p-4 ${className}`}
      onClick={(e) => e.stopPropagation()}
    >
      <div className="flex items-start gap-3">
        <img
          src={logoSrc}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-14 w-14 shrink-0 rounded-full border border-white/10 object-cover"
          onError={(e) => {
            e.currentTarget.src = "/default-avatar.png"
          }}
        />
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-base font-semibold text-white">
            {roomName}
          </h3>
          <p className="mt-0.5 text-xs text-gray-400">
            {memberCount == null
              ? "Loading members…"
              : formatRoomMemberCount(memberCount)}
          </p>
          {roomDescription ? (
            <p className="mt-2 line-clamp-3 text-sm leading-relaxed text-gray-300">
              {roomDescription}
            </p>
          ) : null}
        </div>
      </div>

      <button
        type="button"
        onClick={(e) => void handleAction(e)}
        disabled={actionBusy}
        className="mt-4 w-full rounded-lg bg-green-500/25 px-4 py-2.5 text-sm font-semibold text-green-100 transition hover:bg-green-500/35 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {actionBusy
          ? isMember
            ? "Opening…"
            : "Joining…"
          : isMember
            ? "Open Room"
            : "Join Room"}
      </button>
    </div>
  )
}
