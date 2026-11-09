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
} from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import { tradeRoomBroadcastMiniPanelPosition } from "@/lib/livekit/client/tradeRoomBroadcastMiniPlayerLayout.ts"
import {
  minimizeTradeRoomBroadcastStudioForBrowsing,
  presentTradeRoomBroadcastStudio,
} from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import TradeRoomBroadcastHostSidebar from "./TradeRoomBroadcastHostSidebar.tsx"
import TradeRoomBroadcastSpeakInviteBanner from "./TradeRoomBroadcastSpeakInviteBanner.tsx"
import TradeRoomBroadcastStudioShell from "./TradeRoomBroadcastStudioShell.tsx"
import { fetchBroadcastConversationJoinPayload } from "@/lib/livekit/client/tradeRoomBroadcastJoinConversation.ts"
import {
  joinTradeRoomBroadcastConversation,
  leaveTradeRoomBroadcastConversation,
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
  voiceSessionActive?: boolean
}

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
  voiceSessionActive = false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const miniPanelPosition = tradeRoomBroadcastMiniPanelPosition(voiceSessionActive)
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
  const streamTitle =
    broadcast.roomTitle?.trim() || broadcasterLabel
  const activeRoomId = broadcast.roomId ?? ""
  const openVoice =
    broadcast.status.voiceMode === "open_voice" &&
    !broadcast.isInConversation &&
    Boolean(accessToken && viewerUserId && activeRoomId)

  const onJoinConversation = async () => {
    const videoElement = videoRef.current
    if (!videoElement || !accessToken || !activeRoomId) return
    await joinTradeRoomBroadcastConversation({
      roomId: activeRoomId,
      videoElement,
      fetchJoin: () =>
        fetchBroadcastConversationJoinPayload(accessToken, activeRoomId),
    })
  }

  const onLeaveConversation = async () => {
    const videoElement = videoRef.current
    if (!videoElement || !accessToken || !activeRoomId) return
    await leaveTradeRoomBroadcastConversation({
      roomId: activeRoomId,
      videoElement,
      fetchLeave: async () => {
        const res = await fetch("/api/livekit/broadcast/leave-conversation", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ roomId: activeRoomId }),
        })
        const payload = (await res.json().catch(() => ({}))) as {
          error?: string
          viewerToken?: {
            token?: string
            livekitUrl?: string
            broadcastSessionId?: string
            broadcasterUserId?: string
            broadcasterDisplayName?: string | null
            startedAt?: string
            voiceMode?: string
            videoSource?: string
            publicLive?: boolean
            visibility?: "public" | "preparing"
          } | null
        }
        if (!res.ok) {
          throw new Error(payload.error || "Could not leave conversation.")
        }
        const vt = payload.viewerToken
        return {
          viewerToken: vt?.token
            ? {
                token: vt.token,
                livekitUrl: vt.livekitUrl!,
                broadcastSessionId: vt.broadcastSessionId!,
                broadcasterUserId: vt.broadcasterUserId ?? "",
                broadcasterDisplayName: vt.broadcasterDisplayName ?? null,
                startedAt: vt.startedAt ?? new Date().toISOString(),
                voiceMode: vt.voiceMode as "broadcast_only" | "open_voice" | undefined,
                videoSource: vt.videoSource as "screen" | "camera" | "obs" | undefined,
                publicLive: vt.publicLive,
                visibility: vt.visibility,
              }
            : null,
        }
      },
    })
  }

  const speakInviteBanner =
    broadcast.speakInviteNotice && accessToken && activeRoomId ? (
      <TradeRoomBroadcastSpeakInviteBanner
        roomId={activeRoomId}
        accessToken={accessToken}
        invitationId={broadcast.speakInviteNotice.invitationId}
        busy={broadcast.isBusy || broadcast.speakerUpgradeInFlight}
      />
    ) : null

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
      {openVoice ? (
        <button
          type="button"
          disabled={broadcast.isBusy}
          className="rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-100"
          onClick={() => void onJoinConversation()}
        >
          Join conversation
        </button>
      ) : null}
      {broadcast.isInConversation ? (
        <button
          type="button"
          disabled={broadcast.isBusy}
          className="rounded-lg border border-white/15 px-3 py-2 text-sm"
          onClick={() => void onLeaveConversation()}
        >
          Leave conversation
        </button>
      ) : null}
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
        {speakInviteBanner ? (
          <div className="border-t border-white/10 bg-zinc-950/95 p-2">{speakInviteBanner}</div>
        ) : null}
        <div className="flex flex-wrap items-center gap-2 border-t border-white/10 bg-zinc-950/95 px-2 py-2">
          <p className="min-w-0 basis-full truncate text-[11px] font-medium text-white/90">
            {streamTitle}
          </p>
          <span className="text-[10px] text-white/50">{connLabel}</span>
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
            className="rounded-md border border-white/15 p-1 text-white"
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
          </button>
          <button
            type="button"
            className="rounded-md bg-emerald-700 px-2 py-1 text-xs font-semibold text-white"
            onClick={() => presentTradeRoomBroadcastStudio()}
          >
            Expand
          </button>
          <button
            type="button"
            className="ml-auto rounded-md bg-red-600 px-2 py-1 text-xs font-semibold text-white"
            onClick={() => setConfirmLeave(true)}
          >
            Leave stream
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

  const studioMode = canModerateStream ? "moderator" : "viewer"

  return (
    <TradeRoomBroadcastStudioShell
      mode={studioMode}
      title={streamTitle}
      headerMeta={
        <>
          <span className="rounded bg-red-600 px-1.5 py-0.5 font-bold text-white">LIVE</span>
          <span>
            {broadcast.localViewerCount || broadcast.status.viewerCount || 0} watching
          </span>
          <span className="text-white/50">{connLabel}</span>
        </>
      }
      headerActions={
        <button
          type="button"
          className="rounded-lg border border-white/15 p-2"
          aria-label="Minimize and keep watching while you browse"
          onClick={() => minimizeTradeRoomBroadcastStudioForBrowsing()}
        >
          <Minimize2 size={18} />
        </button>
      }
      toolbar={
        <>
          {speakInviteBanner}
          {controlButtons}
        </>
      }
      video={
        <>
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
        </>
      }
      sidebar={
        accessToken ? (
          <TradeRoomBroadcastHostSidebar
            accessToken={accessToken}
            className="h-full min-h-0"
            sidebarLayout={canModerateStream ? "host" : "viewer"}
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
        ) : null
      }
      confirmDialog={
        confirmLeave ? (
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
        ) : null
      }
    />
  )
}
