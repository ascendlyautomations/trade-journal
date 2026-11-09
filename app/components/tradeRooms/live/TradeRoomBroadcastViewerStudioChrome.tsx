"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { ConnectionState } from "livekit-client"
import {
  Hand,
  Mic,
  MicOff,
  Minimize2,
  Radio,
  Volume2,
  VolumeX,
  X,
} from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastHostSidebar from "./TradeRoomBroadcastHostSidebar.tsx"
import {
  leaveTradeRoomBroadcastViewer,
  sendTradeRoomBroadcastChatMessage,
  setTradeRoomBroadcastStudioPresentation,
  syncTradeRoomBroadcastViewerVideoElement,
  toggleTradeRoomBroadcastRaisedHand,
  toggleTradeRoomBroadcastStreamListenMuted,
  toggleTradeRoomBroadcastViewerMicMuted,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility.ts"

type Props = {
  accessToken: string | null
  viewerUserId: string | null
  viewerDisplayName: string
  viewerAvatarUrl: string | null
  canModerateStream?: boolean
  canActOnTarget?: (targetUserId: string) => boolean
}

const miniPanelPosition =
  "fixed right-[max(0.5rem,env(safe-area-inset-right))] z-[9990] pointer-events-auto max-md:bottom-[calc(var(--app-tab-bar-offset,0px)+0.5rem)] md:bottom-[max(0.75rem,env(safe-area-inset-bottom))]"

function connectionHeadline(state: ConnectionState): string {
  switch (state) {
    case ConnectionState.Connected:
      return "Connected"
    case ConnectionState.Connecting:
      return "Connecting…"
    case ConnectionState.Reconnecting:
    case ConnectionState.SignalReconnecting:
      return "Reconnecting…"
    case ConnectionState.Disconnected:
      return "Disconnected"
    default:
      return String(state)
  }
}

export default function TradeRoomBroadcastViewerStudioChrome({
  accessToken,
  viewerUserId,
  viewerDisplayName,
  viewerAvatarUrl,
  canModerateStream = false,
  canActOnTarget = () => false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const chromeActive = useMemo(
    () => tradeRoomBroadcastGlobalChromeVisible(broadcast),
    [broadcast]
  )
  const videoRef = useRef<HTMLVideoElement>(null)
  const [confirmLeave, setConfirmLeave] = useState(false)

  const bindViewerVideo = useCallback(
    (el: HTMLVideoElement | null) => {
      ;(videoRef as React.MutableRefObject<HTMLVideoElement | null>).current = el
      if (el && chromeActive) {
        syncTradeRoomBroadcastViewerVideoElement(el)
      }
    },
    [chromeActive]
  )

  useEffect(() => {
    if (chromeActive && videoRef.current) {
      syncTradeRoomBroadcastViewerVideoElement(videoRef.current)
    }
  }, [chromeActive, broadcast.connectionState, broadcast.status.videoSource])

  if (!chromeActive || broadcast.isPublishing) {
    return null
  }

  const connLabel = connectionHeadline(broadcast.connectionState)
  const isConnected =
    broadcast.connectionState === ConnectionState.Connected ||
    broadcast.connectionState === ConnectionState.Reconnecting
  const canModerateLiveParticipants = broadcast.isWatching || broadcast.isInConversation
  const broadcasterLabel =
    broadcast.status.broadcasterDisplayName?.trim() || "Live stream"

  const leaveStream = async () => {
    setConfirmLeave(false)
    setTradeRoomBroadcastStudioPresentation("hidden")
    await leaveTradeRoomBroadcastViewer()
  }

  const controlButtons = (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={
          broadcast.isInConversation && !broadcast.viewerMicPublishReady
        }
        aria-label={
          broadcast.isInConversation
            ? broadcast.viewerMicMuted
              ? "Unmute your mic"
              : "Mute your mic"
            : broadcast.streamListenMuted
              ? "Unmute stream"
              : "Mute stream"
        }
        className="inline-flex items-center gap-2 rounded-lg border border-white/15 px-3 py-2 text-sm"
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
            <MicOff size={16} />
          ) : (
            <Mic size={16} />
          )
        ) : broadcast.streamListenMuted ? (
          <VolumeX size={16} />
        ) : (
          <Volume2 size={16} />
        )}
        {broadcast.isInConversation
          ? broadcast.viewerMicMuted
            ? "Mic off"
            : "Mic on"
          : broadcast.streamListenMuted
            ? "Muted"
            : "Sound on"}
      </button>
      {accessToken && viewerUserId ? (
        <button
          type="button"
          aria-label={broadcast.localHandRaised ? "Lower hand" : "Raise hand"}
          className={`inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm ${
            broadcast.localHandRaised
              ? "border-amber-400/40 bg-amber-500/20 text-amber-100"
              : "border-white/15"
          }`}
          onClick={() =>
            void toggleTradeRoomBroadcastRaisedHand({
              accessToken,
              userId: viewerUserId,
            })
          }
        >
          <Hand size={16} />
          {broadcast.localHandRaised ? "Hand raised" : "Raise hand"}
        </button>
      ) : null}
      <button
        type="button"
        className="ml-auto rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-500"
        onClick={() => setConfirmLeave(true)}
      >
        Leave stream
      </button>
    </div>
  )

  if (broadcast.studioPresentation === "mini") {
    return (
      <div
        className={`${miniPanelPosition} w-[min(320px,calc(100vw-24px))] overflow-hidden rounded-xl border border-red-500/25 bg-zinc-950 shadow-2xl`}
      >
        <div className="relative aspect-video bg-black">
          <video
            ref={bindViewerVideo}
            className="h-full w-full object-contain"
            autoPlay
            muted={broadcast.streamListenMuted && !broadcast.isInConversation}
            playsInline
          />
          <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
            <Radio className="h-3 w-3" aria-hidden />
            LIVE
          </span>
          <span className="absolute right-2 top-2 rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white/90">
            {broadcast.localViewerCount || broadcast.status.viewerCount || 0} watching
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2 border-t border-white/10 bg-zinc-950/95 px-2 py-2">
          <p className="min-w-0 flex-1 truncate text-[11px] text-white/80">
            {broadcasterLabel}
          </p>
          <span className="text-[10px] text-white/50">{connLabel}</span>
          <button
            type="button"
            className="rounded-md bg-emerald-700 px-2 py-1 text-xs text-white"
            onClick={() => setTradeRoomBroadcastStudioPresentation("studio")}
          >
            Theater
          </button>
          <button
            type="button"
            className="rounded-md border border-white/15 px-2 py-1 text-xs text-white"
            onClick={() => setConfirmLeave(true)}
          >
            Leave
          </button>
        </div>
        {confirmLeave ? (
          <div className="border-t border-white/10 bg-zinc-900 p-2 text-xs text-white">
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
                className="rounded bg-zinc-700 px-2 py-1"
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

  return (
    <div className="fixed inset-0 z-[9000] flex flex-col bg-zinc-950 text-white">
      <header className="flex shrink-0 items-center gap-3 border-b border-white/10 px-4 py-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">
            {broadcast.roomTitle?.trim() || broadcasterLabel}
          </p>
          <div className="flex items-center gap-2 text-xs text-white/70">
            <span className="rounded bg-red-600 px-1.5 py-0.5 font-bold text-white">LIVE</span>
            <span>{broadcast.localViewerCount || broadcast.status.viewerCount || 0} watching</span>
            <span className="text-white/50">{connLabel}</span>
          </div>
        </div>
        <button
          type="button"
          className="rounded-lg border border-white/15 px-3 py-2 text-xs"
          onClick={() => setTradeRoomBroadcastStudioPresentation("hidden")}
        >
          Exit to room
        </button>
        <button
          type="button"
          className="rounded-lg border border-white/15 p-2"
          aria-label="Minimize player"
          onClick={() => setTradeRoomBroadcastStudioPresentation("mini")}
        >
          <Minimize2 size={18} />
        </button>
        <button
          type="button"
          className="rounded-lg border border-white/15 p-2"
          aria-label="Close theater"
          onClick={() => setTradeRoomBroadcastStudioPresentation("hidden")}
        >
          <X size={18} />
        </button>
      </header>

      <div className="flex min-h-0 flex-1 flex-col p-3">
        <div className="mb-2">{controlButtons}</div>
        <div className="flex min-h-0 flex-1 gap-3">
          <div className="relative min-h-0 min-w-0 flex-1 overflow-hidden rounded-xl bg-black">
            {!isConnected ? (
              <div className="absolute inset-0 flex items-center justify-center text-sm text-gray-400">
                Connecting to stream…
              </div>
            ) : null}
            <video
              ref={bindViewerVideo}
              className="h-full w-full object-contain"
              autoPlay
              muted={broadcast.streamListenMuted && !broadcast.isInConversation}
              playsInline
            />
          </div>

          {accessToken ? (
            <TradeRoomBroadcastHostSidebar
              accessToken={accessToken}
              className="h-full min-h-0 w-[min(380px,38vw)] shrink-0"
              sidebarLayout="viewer"
              isBroadcaster={false}
              canModerateStream={canModerateStream}
              canModerateLiveParticipants={canModerateLiveParticipants}
              canActOnTarget={canActOnTarget}
              chat={{
                userId: viewerUserId,
                displayName: viewerDisplayName,
                avatarUrl: viewerAvatarUrl,
                disabled: !isConnected,
              }}
              onModerationMessage={async (text) => {
                if (!viewerUserId) return
                await sendTradeRoomBroadcastChatMessage({
                  userId: viewerUserId,
                  displayName: viewerDisplayName,
                  avatarUrl: viewerAvatarUrl,
                  text,
                })
              }}
            />
          ) : null}
        </div>
      </div>

      {confirmLeave ? (
        <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-4">
          <div className="max-w-sm rounded-xl bg-zinc-900 p-4">
            <h2 className="text-lg font-semibold">Leave stream?</h2>
            <p className="mt-2 text-sm text-white/70">
              You will disconnect from the livestream.
            </p>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                className="rounded-lg px-3 py-2 text-sm"
                onClick={() => setConfirmLeave(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white"
                onClick={() => void leaveStream()}
              >
                Leave stream
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
