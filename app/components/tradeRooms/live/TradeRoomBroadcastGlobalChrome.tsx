"use client"

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react"
import { ConnectionState } from "livekit-client"
import { Hand, Mic, MicOff, Minimize2, Radio } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import {
  sendTradeRoomBroadcastChatMessage,
  setBroadcastInteractivePollDemand,
  setTradeRoomBroadcastStudioPresentation,
  stopTradeRoomBroadcast,
  syncTradeRoomBroadcastLocalPreviewElement,
  toggleTradeRoomBroadcastMicMuted,
  toggleTradeRoomBroadcastRaisedHand,
  retryTradeRoomBroadcasterCapture,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { getBroadcastPublisherCredentials } from "@/lib/livekit/client/tradeRoomBroadcastPublisherLifecycle.ts"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility.ts"
import TradeRoomBroadcastHostSidebar from "./TradeRoomBroadcastHostSidebar.tsx"
import TradeRoomBroadcastStudioShell from "./TradeRoomBroadcastStudioShell.tsx"
import TradeRoomBroadcastViewerStudioChrome from "./TradeRoomBroadcastViewerStudioChrome.tsx"
import TradeRoomBroadcastScreenOverlayControls from "./TradeRoomBroadcastScreenOverlayControls.tsx"
import TradeRoomBroadcastShareScreenControls from "./TradeRoomBroadcastShareScreenControls.tsx"
import { useUserProfile } from "@/lib/UserProfileProvider"
import {
  getTradeRoomLiveModerationUiContextSnapshot,
  moderationUiCanActOnMember,
  subscribeTradeRoomLiveModerationUiContext,
} from "@/lib/livekit/client/tradeRoomLiveModerationUiContext.ts"
import { tradeRoomBroadcastMiniPanelPosition } from "@/lib/livekit/client/tradeRoomBroadcastMiniPlayerLayout.ts"
import { presentTradeRoomBroadcastStudio } from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"

type Props = {
  accessToken: string | null
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

export default function TradeRoomBroadcastGlobalChrome({
  accessToken,
  voiceSessionActive = false,
}: Props) {
  const { user, profile, loading: profileLoading } = useUserProfile()
  const broadcast = useTradeRoomBroadcast()
  const moderationCtx = useSyncExternalStore(
    subscribeTradeRoomLiveModerationUiContext,
    getTradeRoomLiveModerationUiContextSnapshot,
    getTradeRoomLiveModerationUiContextSnapshot
  )
  const chromeActive = useMemo(
    () => tradeRoomBroadcastGlobalChromeVisible(broadcast),
    [broadcast]
  )
  const isViewerStudioRole =
    broadcast.isWatching &&
    !broadcast.isPublishing &&
    (broadcast.role === "viewer" || broadcast.role === "conversation")
  const chatUserId = user?.id ?? broadcast.status.broadcasterUserId ?? null
  const chatDisplayName =
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    broadcast.status.broadcasterDisplayName?.trim() ||
    "Broadcaster"
  const chatAvatarUrl = profile?.avatar_url ?? null
  const previewRef = useRef<HTMLVideoElement>(null)
  const [confirmEnd, setConfirmEnd] = useState(false)

  const bindPreview = useCallback(
    (el: HTMLVideoElement | null) => {
      ;(previewRef as React.MutableRefObject<HTMLVideoElement | null>).current = el
      if (el && chromeActive) syncTradeRoomBroadcastLocalPreviewElement(el)
    },
    [chromeActive]
  )

  useEffect(() => {
    if (chromeActive && previewRef.current) {
      syncTradeRoomBroadcastLocalPreviewElement(previewRef.current)
    }
  }, [chromeActive, broadcast.connectionState, broadcast.publisherCaptureDegraded])

  useEffect(() => {
    setBroadcastInteractivePollDemand(
      "global-studio",
      Boolean(accessToken && chromeActive),
      accessToken
    )
    return () => setBroadcastInteractivePollDemand("global-studio", false)
  }, [accessToken, chromeActive, broadcast.roomId])

  const [elapsed, setElapsed] = useState("00:00")
  useEffect(() => {
    if (!chromeActive || !broadcast.status.startedAt) {
      return
    }
    const start = new Date(broadcast.status.startedAt).getTime()
    const tick = () => {
      const sec = Math.max(0, Math.floor((Date.now() - start) / 1000))
      const m = Math.floor(sec / 60)
      const s = sec % 60
      setElapsed(`${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`)
    }
    const first = window.setTimeout(tick, 0)
    const id = window.setInterval(tick, 1000)
    return () => {
      window.clearTimeout(first)
      window.clearInterval(id)
    }
  }, [chromeActive, broadcast.status.startedAt])

  const elapsedDisplay =
    !chromeActive || !broadcast.status.startedAt ? "00:00" : elapsed

  if (!chromeActive) {
    return null
  }

  if (isViewerStudioRole) {
    return (
      <TradeRoomBroadcastViewerStudioChrome
        accessToken={accessToken}
        viewerUserId={user?.id ?? null}
        viewerDisplayName={chatDisplayName}
        viewerAvatarUrl={chatAvatarUrl}
        canModerateStream={
          moderationCtx.canModerateRoom || moderationCtx.canManageRoom
        }
        canActOnTarget={(targetUserId) =>
          moderationUiCanActOnMember(moderationCtx, targetUserId)
        }
        voiceSessionActive={voiceSessionActive}
      />
    )
  }

  const miniPanelPosition = tradeRoomBroadcastMiniPanelPosition(voiceSessionActive)
  const streamTitle = broadcast.roomTitle?.trim() || "Trade Room"

  const sessionId =
    broadcast.status.broadcastSessionId ??
    broadcast.publisherSessionId ??
    getBroadcastPublisherCredentials()?.sessionId ??
    ""
  const activeRoomId =
    broadcast.roomId ?? getBroadcastPublisherCredentials()?.roomId ?? ""

  const endStream = async () => {
    if (!sessionId || !activeRoomId) return
    const creds = getBroadcastPublisherCredentials()
    const token = accessToken ?? creds?.accessToken ?? null
    await stopTradeRoomBroadcast({
      roomId: activeRoomId,
      sessionId,
      fetchStop:
        token
          ? async () => {
              await fetch("/api/livekit/broadcast/stop", {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                  Authorization: `Bearer ${token}`,
                },
                body: JSON.stringify({
                  roomId: activeRoomId,
                  sessionId,
                }),
              })
            }
          : undefined,
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

  const connLabel = connectionHeadline(broadcast.connectionState)
  const showRetry =
    broadcast.publisherCaptureDegraded ||
    broadcast.connectionState === ConnectionState.Disconnected ||
    Boolean(broadcast.broadcasterPreviewError)

  const statusBanner =
    broadcast.broadcasterPreviewError ??
    (broadcast.connectionState === ConnectionState.Reconnecting ||
    broadcast.connectionState === ConnectionState.SignalReconnecting
      ? "Reconnecting to LiveKit…"
      : broadcast.connectionState === ConnectionState.Disconnected
        ? "LiveKit disconnected. Retry capture or end the stream."
        : null)

  const streamControls = (
    <div className="mb-2 flex flex-col gap-2">
      <TradeRoomBroadcastShareScreenControls />
      <TradeRoomBroadcastScreenOverlayControls />
      {statusBanner ? (
        <p className="rounded-lg border border-amber-400/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
          {statusBanner}
        </p>
      ) : null}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="flex min-w-0 flex-wrap items-center gap-3 text-xs text-white/60">
          <span>{connLabel}</span>
          <span className="inline-flex items-center gap-1 text-amber-300">
            <Hand size={14} />
            {broadcast.raisedHandIdentities.length} raised
          </span>
        </div>
        <div className="ml-auto flex shrink-0 flex-wrap items-center justify-end gap-2">
          {showRetry ? (
            <button
              type="button"
              disabled={broadcast.isBusy}
              className="rounded-lg border border-white/15 px-3 py-2 text-sm"
              onClick={() => void retryTradeRoomBroadcasterCapture()}
            >
              Retry
            </button>
          ) : null}
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
            disabled={broadcast.isBusy}
            className="inline-flex items-center gap-2 rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-500 disabled:opacity-60"
            onClick={() => setConfirmEnd(true)}
          >
            End stream
          </button>
        </div>
      </div>
    </div>
  )

  if (broadcast.studioPresentation === "mini") {
    return (
      <div
        className={`${miniPanelPosition} w-[min(320px,calc(100vw-24px))] overflow-hidden rounded-xl border border-red-500/25 bg-zinc-950 shadow-2xl`}
      >
        <div className="relative aspect-video bg-black">
          <video
            ref={bindPreview}
            className="h-full w-full object-contain"
            autoPlay
            muted
            playsInline
          />
          <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
            <Radio className="h-3 w-3" aria-hidden />
            LIVE
          </span>
          <span className="absolute right-2 top-2 rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white/90">
            {broadcast.localViewerCount} watching
          </span>
          {statusBanner ? (
            <div className="absolute inset-x-0 bottom-0 bg-black/85 px-2 py-1.5 text-[10px] leading-snug text-amber-100">
              {statusBanner}
            </div>
          ) : null}
        </div>
        <div className="border-t border-white/10 bg-zinc-950/95 px-2 py-2">
          <TradeRoomBroadcastShareScreenControls compact className="mb-2 border-0 bg-transparent p-0" />
        </div>
        <div className="flex flex-wrap items-center gap-2 border-t border-white/10 bg-zinc-950/95 px-2 py-2">
          <p className="min-w-0 flex-1 truncate text-[11px] font-medium text-white/90">
            {streamTitle}
          </p>
          <span className="text-[10px] text-white/50">{connLabel}</span>
          <span className="text-[10px] text-white/50">{elapsedDisplay}</span>
          <button
            type="button"
            className="rounded-md bg-emerald-700 px-2 py-1 text-xs font-semibold text-white"
            onClick={() => presentTradeRoomBroadcastStudio()}
          >
            Expand
          </button>
          {showRetry ? (
            <button
              type="button"
              disabled={broadcast.isBusy}
              className="rounded-md border border-white/15 px-2 py-1 text-xs text-white"
              onClick={() => void retryTradeRoomBroadcasterCapture()}
            >
              Retry
            </button>
          ) : null}
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
            disabled={broadcast.isBusy}
            className="ml-auto rounded-md bg-red-600 px-2 py-1 text-xs font-semibold text-white disabled:opacity-60"
            onClick={() => setConfirmEnd(true)}
          >
            End stream
          </button>
        </div>
        {confirmEnd ? (
          <div className="border-t border-white/10 bg-zinc-900 p-2 text-xs text-white">
            End stream for everyone?
            <div className="mt-2 flex gap-2">
              <button
                type="button"
                className="rounded bg-red-600 px-2 py-1"
                onClick={() => void endStream()}
              >
                End stream
              </button>
              <button
                type="button"
                className="rounded bg-zinc-700 px-2 py-1"
                onClick={() => setConfirmEnd(false)}
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
    <TradeRoomBroadcastStudioShell
      mode="host"
      title={broadcast.roomTitle ?? "Trade Room"}
      headerMeta={
        <>
          <span className="rounded bg-red-600 px-1.5 py-0.5 font-bold text-white">LIVE</span>
          <span>{elapsedDisplay}</span>
          <span>{broadcast.localViewerCount} watching</span>
          <span className="text-white/50">{connLabel}</span>
        </>
      }
      headerActions={
        <button
          type="button"
          className="rounded-lg border border-white/15 p-2"
          aria-label="Minimize studio"
          onClick={() => setTradeRoomBroadcastStudioPresentation("mini")}
        >
          <Minimize2 size={18} />
        </button>
      }
      videoColumnPrefix={streamControls}
      video={
        <video
          ref={bindPreview}
          className="h-full w-full object-contain"
          autoPlay
          muted
          playsInline
        />
      }
      sidebar={
        accessToken ? (
          <TradeRoomBroadcastHostSidebar
            accessToken={accessToken}
            className="h-full min-h-0"
            isBroadcaster
            canModerateStream
            canActOnTarget={(targetUserId) =>
              moderationUiCanActOnMember(moderationCtx, targetUserId)
            }
            canModerateLiveParticipants
            chat={{
              userId: chatUserId,
              displayName: chatDisplayName,
              avatarUrl: chatAvatarUrl,
              disabled: Boolean(profileLoading && !chatUserId),
              authLoading: profileLoading && !chatUserId,
            }}
            onModerationMessage={postModerationChatLine}
          />
        ) : null
      }
      confirmDialog={
        confirmEnd ? (
          <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-4">
            <div className="max-w-sm rounded-xl bg-zinc-900 p-4">
              <h2 className="text-lg font-semibold">End stream?</h2>
              <p className="mt-2 text-sm text-white/70">
                Ends the server session even if LiveKit is disconnected.
              </p>
              <div className="mt-4 flex justify-end gap-2">
                <button
                  type="button"
                  className="rounded-lg px-3 py-2 text-sm"
                  onClick={() => setConfirmEnd(false)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={broadcast.isBusy}
                  className="rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold disabled:opacity-60"
                  onClick={() => void endStream()}
                >
                  End stream
                </button>
              </div>
            </div>
          </div>
        ) : null
      }
    />
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
