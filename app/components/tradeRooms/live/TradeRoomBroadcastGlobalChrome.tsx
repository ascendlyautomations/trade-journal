"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { ConnectionState } from "livekit-client"
import { Hand, Mic, MicOff, Minimize2 } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import {
  refreshBroadcastInteractiveState,
  sendTradeRoomBroadcastChatMessage,
  setTradeRoomBroadcastStudioPresentation,
  stopTradeRoomBroadcast,
  syncTradeRoomBroadcastLocalPreviewElement,
  toggleTradeRoomBroadcastMicMuted,
  toggleTradeRoomBroadcastRaisedHand,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import TradeRoomBroadcastHostSidebar from "./TradeRoomBroadcastHostSidebar.tsx"
import { useUserProfile } from "@/lib/UserProfileProvider"

type Props = {
  accessToken: string | null
}

export default function TradeRoomBroadcastGlobalChrome({ accessToken }: Props) {
  const { user, profile, loading: profileLoading } = useUserProfile()
  const broadcast = useTradeRoomBroadcast()
  const chatUserId = user?.id ?? broadcast.status.broadcasterUserId ?? null
  const chatDisplayName =
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    broadcast.status.broadcasterDisplayName?.trim() ||
    "Broadcaster"
  const chatAvatarUrl = profile?.avatar_url ?? null
  const previewRef = useRef<HTMLVideoElement>(null)
  const [confirmEnd, setConfirmEnd] = useState(false)
  const [miniPos, setMiniPos] = useState({ x: 16, y: 16 })

  const bindPreview = useCallback(
    (el: HTMLVideoElement | null) => {
      ;(previewRef as React.MutableRefObject<HTMLVideoElement | null>).current = el
      if (el && broadcast.isPublishing) syncTradeRoomBroadcastLocalPreviewElement(el)
    },
    [broadcast.isPublishing]
  )

  useEffect(() => {
    if (!accessToken || !broadcast.isPublishing) return
    void refreshBroadcastInteractiveState(accessToken)
    const id = window.setInterval(() => {
      void refreshBroadcastInteractiveState(accessToken)
    }, 4000)
    return () => window.clearInterval(id)
  }, [accessToken, broadcast.isPublishing, broadcast.roomId])

  const elapsed = useMemo(() => {
    if (!broadcast.status.startedAt) return "00:00"
    const start = new Date(broadcast.status.startedAt).getTime()
    const sec = Math.max(0, Math.floor((Date.now() - start) / 1000))
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
  }, [broadcast.status.startedAt, broadcast.connectionState])

  if (!broadcast.isPublishing || broadcast.studioPresentation === "hidden") {
    return null
  }

  const endStream = async () => {
    if (!broadcast.roomId || !broadcast.status.broadcastSessionId || !accessToken) return
    await stopTradeRoomBroadcast({
      roomId: broadcast.roomId,
      sessionId: broadcast.status.broadcastSessionId,
      fetchStop: async () => {
        await fetch("/api/livekit/broadcast/stop", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            roomId: broadcast.roomId,
            sessionId: broadcast.status.broadcastSessionId,
          }),
        })
      },
    })
    setConfirmEnd(false)
    setTradeRoomBroadcastStudioPresentation("hidden")
  }

  const postModerationChatLine = async (text: string) => {
    if (!chatUserId) return
    await sendTradeRoomBroadcastChatMessage({
      userId: chatUserId,
      displayName: chatDisplayName,
      avatarUrl: chatAvatarUrl,
      text,
    })
  }

  const streamControls = (
    <div className="mb-2 flex items-center gap-3">
      <div className="flex min-w-0 flex-wrap items-center gap-3">
        <span className="text-xs text-white/60">
          {broadcast.connectionState === ConnectionState.Connected
            ? "Connected"
            : broadcast.connectionState}
        </span>
        <span className="inline-flex items-center gap-1 text-xs text-amber-300">
          <Hand size={14} />
          {broadcast.raisedHandIdentities.length} raised
        </span>
      </div>
      <div className="ml-auto flex shrink-0 flex-wrap items-center justify-end gap-2">
        <button
          type="button"
          className="inline-flex items-center gap-2 rounded-lg border border-white/15 px-3 py-2 text-sm"
          onClick={() => void toggleTradeRoomBroadcastMicMuted()}
        >
          {broadcast.broadcasterMicMuted ? <MicOff size={16} /> : <Mic size={16} />}
          {broadcast.broadcasterMicMuted ? "Mic off" : "Mic on"}
        </button>
        <button
          type="button"
          className="inline-flex items-center gap-2 rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-500"
          onClick={() => setConfirmEnd(true)}
        >
          End stream
        </button>
      </div>
    </div>
  )

  if (broadcast.studioPresentation === "mini") {
    return (
      <div
        className="fixed z-[9000] w-[min(320px,calc(100vw-24px))] overflow-hidden rounded-xl border border-white/10 bg-black shadow-2xl"
        style={{ right: miniPos.x, bottom: miniPos.y }}
      >
        <div className="relative aspect-video bg-black">
          <video ref={bindPreview} className="h-full w-full object-contain" autoPlay muted playsInline />
          <span className="absolute left-2 top-2 rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
            LIVE
          </span>
        </div>
        <div className="flex items-center gap-2 bg-zinc-950/95 px-2 py-2">
          <button
            type="button"
            className="rounded-md bg-emerald-700 px-2 py-1 text-xs text-white"
            onClick={() => setTradeRoomBroadcastStudioPresentation("studio")}
          >
            Restore
          </button>
          <button
            type="button"
            className="rounded-md p-1 text-white/80"
            aria-label={broadcast.broadcasterMicMuted ? "Unmute" : "Mute"}
            onClick={() => void toggleTradeRoomBroadcastMicMuted()}
          >
            {broadcast.broadcasterMicMuted ? <MicOff size={16} /> : <Mic size={16} />}
          </button>
          <button
            type="button"
            className="ml-auto rounded-md bg-red-600 px-2 py-1 text-xs text-white"
            onClick={() => setConfirmEnd(true)}
          >
            End stream
          </button>
        </div>
        {confirmEnd ? (
          <div className="border-t border-white/10 bg-zinc-900 p-2 text-xs text-white">
            End stream for everyone?
            <div className="mt-2 flex gap-2">
              <button type="button" className="rounded bg-red-600 px-2 py-1" onClick={() => void endStream()}>
                End stream
              </button>
              <button type="button" className="rounded bg-zinc-700 px-2 py-1" onClick={() => setConfirmEnd(false)}>
                Cancel
              </button>
            </div>
          </div>
        ) : null}
      </div>
    )
  }

  return (
    <div className="fixed inset-0 z-[9000] flex flex-col bg-zinc-950 text-white">
      <header className="flex shrink-0 items-center gap-3 border-b border-white/10 px-4 py-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{broadcast.roomTitle ?? "Trade Room"}</p>
          <div className="flex items-center gap-2 text-xs text-white/70">
            <span className="rounded bg-red-600 px-1.5 py-0.5 font-bold text-white">LIVE</span>
            <span>{elapsed}</span>
            <span>{broadcast.localViewerCount} watching</span>
          </div>
        </div>
        <button
          type="button"
          className="rounded-lg border border-white/15 p-2"
          aria-label="Minimize studio"
          onClick={() => setTradeRoomBroadcastStudioPresentation("mini")}
        >
          <Minimize2 size={18} />
        </button>
      </header>

      <div className="flex min-h-0 flex-1 flex-col p-3">
        <div className="flex min-h-0 flex-1 gap-3">
          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            {streamControls}
            <div className="relative min-h-0 flex-1 overflow-hidden rounded-xl bg-black">
              <video ref={bindPreview} className="h-full w-full object-contain" autoPlay muted playsInline />
              {broadcast.broadcasterPreviewError ? (
                <p className="absolute inset-x-0 bottom-0 bg-red-950/90 p-2 text-sm text-red-100">
                  {broadcast.broadcasterPreviewError}
                </p>
              ) : null}
            </div>
          </div>

          {accessToken ? (
            <TradeRoomBroadcastHostSidebar
              accessToken={accessToken}
              className="h-full min-h-0 w-[min(380px,38vw)] shrink-0"
              chat={{
                userId: chatUserId,
                displayName: chatDisplayName,
                avatarUrl: chatAvatarUrl,
                disabled: Boolean(profileLoading && !chatUserId),
                authLoading: profileLoading && !chatUserId,
              }}
              onModerationMessage={postModerationChatLine}
            />
          ) : null}
        </div>
      </div>

      {confirmEnd ? (
        <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-4">
          <div className="max-w-sm rounded-xl bg-zinc-900 p-4">
            <h2 className="text-lg font-semibold">End stream?</h2>
            <p className="mt-2 text-sm text-white/70">Everyone will be disconnected from this livestream.</p>
            <div className="mt-4 flex justify-end gap-2">
              <button type="button" className="rounded-lg px-3 py-2 text-sm" onClick={() => setConfirmEnd(false)}>
                Cancel
              </button>
              <button
                type="button"
                className="rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold"
                onClick={() => void endStream()}
              >
                End stream
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}

export function TradeRoomBroadcastViewerHandControl({
  accessToken,
  userId,
}: {
  accessToken: string | null
  userId: string | null
}) {
  const broadcast = useTradeRoomBroadcast()
  if (!broadcast.isWatching || !accessToken || !userId) return null
  return (
    <button
      type="button"
      className={`inline-flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${
        broadcast.localHandRaised ? "bg-amber-400 text-black" : "bg-white/10 text-white"
      }`}
      onClick={() => void toggleTradeRoomBroadcastRaisedHand({ accessToken, userId })}
    >
      <Hand size={16} />
      {broadcast.localHandRaised ? "Lower hand" : "Raise hand"}
    </button>
  )
}
