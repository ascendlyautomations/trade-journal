"use client"

import { Hand, Mic, MicOff, Radio, Volume2, VolumeX, X } from "lucide-react"
import { useRouter } from "next/navigation"
import { useMemo, useState } from "react"
import { useTradeRoomBroadcast } from "@/app/components/tradeRooms/live/useTradeRoomBroadcast"
import {
  leaveTradeRoomBroadcastViewer,
  setTradeRoomBroadcastStudioPresentation,
  toggleTradeRoomBroadcastMicMuted,
  toggleTradeRoomBroadcastRaisedHand,
  toggleTradeRoomBroadcastStreamListenMuted,
  toggleTradeRoomBroadcastViewerMicMuted,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility.ts"
import { presentTradeRoomBroadcastStudio } from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import { useUserProfile } from "@/lib/UserProfileProvider"

type Props = {
  accessToken: string | null
  onOpenRoom?: () => void
}

/** Full-width persistent livestream bar (mobile web shell / in-room). */
export default function TradeRoomBroadcastPersistentBar({
  accessToken,
  onOpenRoom,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const router = useRouter()
  const { user } = useUserProfile()
  const [confirmLeave, setConfirmLeave] = useState(false)

  const visible = useMemo(
    () =>
      tradeRoomBroadcastGlobalChromeVisible(broadcast) &&
      broadcast.studioPresentation !== "studio",
    [broadcast]
  )

  if (!visible) return null

  const title = broadcast.roomTitle?.trim() || "Live stream"
  const isHost = broadcast.isPublishing && broadcast.role === "broadcaster"
  const isViewer =
    broadcast.isWatching &&
    (broadcast.role === "viewer" || broadcast.role === "conversation")

  const openStream = () => {
    onOpenRoom?.()
    const roomId = broadcast.roomId?.trim()
    if (roomId) {
      router.push(`/community?room=${encodeURIComponent(roomId)}`)
    }
    presentTradeRoomBroadcastStudio()
  }

  const leaveStream = async () => {
    setConfirmLeave(false)
    setTradeRoomBroadcastStudioPresentation("hidden")
    await leaveTradeRoomBroadcastViewer()
  }

  const subtitle = isHost
    ? "You're live — tap to open stream"
    : isViewer
      ? broadcast.isInConversation
        ? "On stage — tap to open stream"
        : "Watching live — tap to open stream"
      : "Live session active"

  return (
    <div
      className="border-t border-red-500/40 bg-[color:var(--chrome,#0b1f3a)]/98"
      data-tt-trade-room-broadcast-bar
      role="region"
      aria-label="Live stream session"
    >
      <div className="flex items-center gap-2 px-3 py-2">
        <button
          type="button"
          onClick={openStream}
          className="flex min-w-0 flex-1 items-center gap-2.5 text-left"
        >
          <span className="inline-flex shrink-0 items-center rounded bg-red-600 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-white">
            <Radio className="mr-0.5 inline h-3 w-3" aria-hidden />
            Live
          </span>
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[13px] font-semibold text-[color:var(--chrome-foreground,#f3f4f6)]">
              {title}
            </span>
            <span className="block truncate text-[11px] text-[color:var(--tt-text-muted,#a8b3c2)]">
              {subtitle}
            </span>
          </span>
        </button>

        {isViewer ? (
          <>
            <button
              type="button"
              aria-label={broadcast.localHandRaised ? "Lower hand" : "Raise hand"}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[color:var(--chrome-foreground,#f3f4f6)] active:bg-white/10"
              disabled={!accessToken || !user?.id}
              onClick={() => {
                if (!accessToken || !user?.id) return
                void toggleTradeRoomBroadcastRaisedHand({
                  accessToken,
                  userId: user.id,
                })
              }}
            >
              <Hand
                className={`h-4 w-4 ${broadcast.localHandRaised ? "text-[#4EC4E0]" : ""}`}
                aria-hidden
              />
            </button>
            <button
              type="button"
              aria-label={
                broadcast.isInConversation
                  ? broadcast.viewerMicMuted
                    ? "Unmute mic"
                    : "Mute mic"
                  : broadcast.streamListenMuted
                    ? "Unmute stream"
                    : "Mute stream"
              }
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[color:var(--chrome-foreground,#f3f4f6)] active:bg-white/10"
              onClick={() => {
                if (broadcast.isInConversation) {
                  void toggleTradeRoomBroadcastViewerMicMuted()
                } else {
                  toggleTradeRoomBroadcastStreamListenMuted()
                }
              }}
            >
              {broadcast.isInConversation ? (
                broadcast.viewerMicMuted ? (
                  <MicOff className="h-4 w-4" aria-hidden />
                ) : (
                  <Mic className="h-4 w-4" aria-hidden />
                )
              ) : broadcast.streamListenMuted ? (
                <VolumeX className="h-4 w-4" aria-hidden />
              ) : (
                <Volume2 className="h-4 w-4" aria-hidden />
              )}
            </button>
            <button
              type="button"
              aria-label="Leave stream"
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-red-400 active:bg-red-500/10"
              onClick={() => setConfirmLeave(true)}
            >
              <X className="h-4 w-4" aria-hidden />
            </button>
          </>
        ) : isHost ? (
          <>
            <button
              type="button"
              aria-label={broadcast.broadcasterMicMuted ? "Unmute mic" : "Mute mic"}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[color:var(--chrome-foreground,#f3f4f6)] active:bg-white/10"
              onClick={() => void toggleTradeRoomBroadcastMicMuted()}
            >
              {broadcast.broadcasterMicMuted ? (
                <MicOff className="h-4 w-4" aria-hidden />
              ) : (
                <Mic className="h-4 w-4" aria-hidden />
              )}
            </button>
            <button
              type="button"
              aria-label="Open stream controls"
              className="shrink-0 rounded-full bg-[#4EC4E0] px-3 py-1.5 text-[12px] font-semibold text-[#0b1220]"
              onClick={openStream}
            >
              Open
            </button>
          </>
        ) : null}
      </div>

      {confirmLeave ? (
        <div className="border-t border-white/10 bg-black/40 px-3 py-2 text-xs text-white">
          Leave this livestream?
          <div className="mt-2 flex gap-2">
            <button
              type="button"
              className="rounded bg-red-600 px-2 py-1"
              onClick={() => void leaveStream()}
            >
              Leave
            </button>
            <button
              type="button"
              className="rounded bg-white/15 px-2 py-1"
              onClick={() => setConfirmLeave(false)}
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
