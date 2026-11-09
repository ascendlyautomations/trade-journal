"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { ConnectionState } from "livekit-client"
import { Copy, Eye, EyeOff, Mic, MicOff, Radio } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastGoLiveDialog, {
  type GoLiveDialogResult,
} from "./TradeRoomBroadcastGoLiveDialog.tsx"
import {
  setBroadcastInteractivePollDemand,
  setBroadcastPassiveInteractiveContext,
  leaveTradeRoomBroadcastViewer,
  refreshTradeRoomBroadcastStatus,
  startTradeRoomBroadcast,
  publishTradeRoomBroadcastObs,
  setTradeRoomBroadcastRoomTitle,
  setTradeRoomBroadcastStudioPresentation,
  stopTradeRoomBroadcast,
  syncTradeRoomBroadcastLocalPreviewElement,
  setObsStreamKeyRevealed,
  copyObsFieldToClipboard,
  toggleTradeRoomBroadcastMicMuted,
  acknowledgeViewerBroadcastConnectionLost,
  retryTradeRoomBroadcastConversationMicrophone,
  ensureObsIngressCredentials,
  retryTradeRoomBroadcasterCapture,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { getBroadcastPublisherCredentials } from "@/lib/livekit/client/tradeRoomBroadcastPublisherLifecycle.ts"
import { logBroadcast } from "@/lib/livekit/client/tradeRoomBroadcastDiagnostics.ts"
import {
  openTradeRoomBroadcastHostStudio,
  openTradeRoomBroadcastViewerStudio,
} from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "@/lib/livekit/tradeRoomBroadcastVoiceMode.ts"
import { tradeRoomObsGoLiveToRoomEnabled } from "@/lib/livekit/tradeRoomObsGoLiveReadiness.ts"
import { tradeRoomGoLiveButtonDisabled } from "@/lib/livekit/client/tradeRoomGoLiveButtonDisabled.ts"

type Props = {
  roomId: string
  roomTitle?: string
  canGoLive: boolean
  accessToken: string | null
  viewerUserId: string | null
  viewerDisplayName: string
  viewerAvatarUrl: string | null
  canModerateStream?: boolean
  canActOnTarget?: (targetUserId: string) => boolean
}

async function authFetch(
  accessToken: string,
  path: string,
  init?: RequestInit
): Promise<Response> {
  return fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      ...(init?.headers ?? {}),
    },
  })
}

type StatusPayload = {
  live?: boolean
  publicLive?: boolean
  visibility?: "public" | "preparing"
  broadcastSessionId?: string
  broadcasterUserId?: string
  broadcasterDisplayName?: string | null
  startedAt?: string
  viewerCount?: number | null
  voiceMode?: TradeRoomBroadcastVoiceMode
  videoSource?: TradeRoomBroadcastVideoSource
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
  livekitIngressId?: string | null
  ingressStatusSnapshot?: string | null
  hostConnected?: boolean | null
  primaryMediaPublisherConnected?: boolean | null
  broadcasterConnected?: boolean | null
  alreadyLiveElsewhere?: boolean
  error?: string
}

type TokenPayload = StatusPayload & {
  token?: string
  livekitUrl?: string
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
  publicLive?: boolean
  visibility?: "public" | "preparing"
}

export default function TradeRoomBroadcastPanel({
  roomId,
  roomTitle,
  canGoLive,
  accessToken,
  viewerUserId,
  viewerDisplayName,
  viewerAvatarUrl,
  canModerateStream = false,
  canActOnTarget = () => false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const isLive = broadcast.status.live
  /** Viewer-discoverable / room-public: backend canonical `publicLive` only (see `setTradeRoomBroadcastStatus`). */
  const publicLive = broadcast.status.publicLive === true
  /**
   * Private OBS preparation: host publisher + session not public in DB (`publicLive` from store).
   */
  const obsPreparingHost =
    broadcast.isPublishing &&
    broadcast.status.videoSource === "obs" &&
    !publicLive
  /** Host-only: includes LiveKit connect gap before `isPublishing` is set. */
  const obsHostPrivatePrepChrome =
    broadcast.obsBroadcastBootstrapping || obsPreparingHost
  const obsReadyForPublic = tradeRoomObsGoLiveToRoomEnabled({
    obsPreparingHost,
    isBusy: broadcast.isBusy,
    primaryMediaPublisherConnected:
      broadcast.status.primaryMediaPublisherConnected,
  })
  /** Private OBS prep UI (credentials + preview) — not tied to panel expand state. */
  const obsPrivateSetupExpanded =
    broadcast.obsBroadcastBootstrapping ||
    (broadcast.isPublishing &&
      broadcast.status.videoSource === "obs" &&
      !publicLive)
  const encoderConnected =
    broadcast.status.primaryMediaPublisherConnected === true
  const waitingForObsEncoder =
    obsPreparingHost &&
    !encoderConnected &&
    (broadcast.status.ingressStatusSnapshot === "ENDPOINT_INACTIVE" ||
      broadcast.status.ingressStatusSnapshot === "ENDPOINT_BUFFERING" ||
      broadcast.status.ingressStatusSnapshot == null)

  const videoRef = useRef<HTMLVideoElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [goLiveOpen, setGoLiveOpen] = useState(false)

  const bindStreamVideoRef = useCallback(
    (el: HTMLVideoElement | null) => {
      ;(videoRef as React.MutableRefObject<HTMLVideoElement | null>).current = el
      if (!el) return
      if (broadcast.isPublishing) {
        syncTradeRoomBroadcastLocalPreviewElement(el)
      }
    },
    [broadcast.isPublishing]
  )

  const fetchStatus = useCallback(
    async (reconcile = false, lite = false) => {
    if (!accessToken) {
      return { live: false }
    }
    const reconcileQuery = canGoLive && reconcile ? "&reconcile=1" : ""
    const liteQuery =
      !reconcile && lite ? "&lite=1" : ""
    const res = await authFetch(
      accessToken,
      `/api/livekit/broadcast/status?roomId=${encodeURIComponent(roomId)}${reconcileQuery}${liteQuery}`
    )
    const payload = (await res.json().catch(() => ({}))) as StatusPayload
    logBroadcast("status API response", {
      roomId,
      httpStatus: res.status,
      live: payload.live ?? null,
      broadcastSessionId: payload.broadcastSessionId ?? null,
      videoSource: payload.videoSource ?? null,
      visibility: payload.visibility ?? null,
      publicLive: payload.publicLive ?? null,
    })
    if (!res.ok) {
      throw new Error(payload.error || "Could not load stream status.")
    }
    return {
      live: Boolean(payload.live),
      publicLive:
        typeof payload.publicLive === "boolean" ? payload.publicLive : undefined,
      visibility: payload.visibility,
      broadcastSessionId: payload.broadcastSessionId,
      broadcasterUserId: payload.broadcasterUserId,
      broadcasterDisplayName: payload.broadcasterDisplayName,
      startedAt: payload.startedAt,
      viewerCount: payload.viewerCount,
      voiceMode: payload.voiceMode,
      videoSource: payload.videoSource,
      broadcastSource: payload.broadcastSource,
      primaryMediaPublisherIdentity: payload.primaryMediaPublisherIdentity,
      livekitIngressId: payload.livekitIngressId,
      ingressStatusSnapshot: payload.ingressStatusSnapshot,
      hostConnected: payload.hostConnected,
      primaryMediaPublisherConnected: payload.primaryMediaPublisherConnected,
      broadcasterConnected: payload.broadcasterConnected,
      alreadyLiveElsewhere: payload.alreadyLiveElsewhere,
    }
  },
    [accessToken, roomId, canGoLive]
  )

  const statusFetchInFlightRef = useRef(false)

  const runStatusRefresh = useCallback(
    async (reconcile: boolean, lite: boolean) => {
      if (statusFetchInFlightRef.current) return
      statusFetchInFlightRef.current = true
      try {
        await refreshTradeRoomBroadcastStatus(() =>
          fetchStatus(reconcile, lite)
        )
      } finally {
        statusFetchInFlightRef.current = false
      }
    },
    [fetchStatus]
  )

  const retryObsCredentials = useCallback(async () => {
    if (!accessToken || !broadcast.status.broadcastSessionId) return
    await ensureObsIngressCredentials({
      roomId,
      sessionId: broadcast.status.broadcastSessionId,
      accessToken,
      forceRecreate:
        broadcast.obsStudio?.credentialsLostOrUnavailable === true,
    })
    void runStatusRefresh(false, false)
  }, [
    accessToken,
    roomId,
    broadcast.status.broadcastSessionId,
    broadcast.obsStudio?.credentialsLostOrUnavailable,
    runStatusRefresh,
  ])

  const regenerateObsCredentials = useCallback(async () => {
    if (!accessToken || !broadcast.status.broadcastSessionId) return
    await ensureObsIngressCredentials({
      roomId,
      sessionId: broadcast.status.broadcastSessionId,
      accessToken,
      forceRecreate: true,
    })
    void runStatusRefresh(false, false)
  }, [
    accessToken,
    roomId,
    broadcast.status.broadcastSessionId,
    runStatusRefresh,
  ])

  useEffect(() => {
    if (!accessToken || !roomId) return
    void runStatusRefresh(true, false)
    const id = window.setInterval(() => {
      void runStatusRefresh(false, true)
    }, 30_000)
    return () => window.clearInterval(id)
  }, [accessToken, roomId, runStatusRefresh])

  /** OBS prep: lite polls omit LiveKit presence; poll full status so Go live enables when encoder publishes. */
  useEffect(() => {
    if (!accessToken || !roomId || !obsPreparingHost) return
    void runStatusRefresh(false, false)
    const id = window.setInterval(() => {
      void runStatusRefresh(false, false)
    }, 3000)
    return () => window.clearInterval(id)
  }, [accessToken, roomId, obsPreparingHost, runStatusRefresh])

  const fetchStop = useCallback(
    async (sessionId: string) => {
      if (!accessToken) return
      await authFetch(accessToken, "/api/livekit/broadcast/stop", {
        method: "POST",
        body: JSON.stringify({ roomId, sessionId }),
      })
    },
    [accessToken, roomId]
  )

  const parseTokenResponse = (payload: TokenPayload) => {
    if (!payload.token || !payload.livekitUrl || !payload.broadcastSessionId) {
      throw new Error("Invalid stream token response.")
    }
    return {
      token: payload.token,
      livekitUrl: payload.livekitUrl,
      broadcastSessionId: payload.broadcastSessionId,
      broadcasterUserId: payload.broadcasterUserId ?? "",
      broadcasterDisplayName: payload.broadcasterDisplayName ?? null,
      startedAt: payload.startedAt ?? new Date().toISOString(),
      voiceMode: payload.voiceMode ?? "broadcast_only",
      videoSource: payload.videoSource ?? "screen",
      broadcastSource: payload.broadcastSource,
      primaryMediaPublisherIdentity: payload.primaryMediaPublisherIdentity,
      publicLive: payload.publicLive,
      visibility: payload.visibility,
    }
  }

  const runGoLive = useCallback(
    async (setup: GoLiveDialogResult) => {
      if (!accessToken) return
      setGoLiveOpen(false)
      setTradeRoomBroadcastRoomTitle(roomTitle ?? "Trade Room")
      await startTradeRoomBroadcast({
        roomId,
        setup,
        publisherAccessToken: accessToken,
        fetchStop,
        fetchStart: async () => {
          const res = await authFetch(accessToken, "/api/livekit/broadcast/start", {
            method: "POST",
            body: JSON.stringify({
              roomId,
              voiceMode: setup.voiceMode,
              videoSource: setup.videoSource,
            }),
          })
          const payload = (await res.json().catch(() => ({}))) as TokenPayload
          if (!res.ok) {
            throw new Error(payload.error || "Could not go live.")
          }
          return parseTokenResponse(payload)
        },
      })
    },
    [accessToken, roomId, roomTitle, fetchStop]
  )

  const onStopLive = useCallback(async () => {
    const sessionId =
      broadcast.status.broadcastSessionId?.trim() ||
      broadcast.publisherSessionId?.trim() ||
      getBroadcastPublisherCredentials()?.sessionId?.trim() ||
      ""
    if (!sessionId) return
    await stopTradeRoomBroadcast({
      roomId: broadcast.roomId ?? roomId,
      sessionId,
      fetchStop: () => fetchStop(sessionId),
    })
    setTradeRoomBroadcastStudioPresentation("hidden")
    void runStatusRefresh(true, false)
  }, [
    broadcast.status.broadcastSessionId,
    broadcast.publisherSessionId,
    broadcast.roomId,
    roomId,
    fetchStop,
    runStatusRefresh,
  ])

  useEffect(() => {
    if (
      !accessToken ||
      !viewerUserId ||
      !broadcast.status.live ||
      broadcast.isPublishing ||
      !publicLive
    ) {
      setBroadcastPassiveInteractiveContext(null)
      setBroadcastInteractivePollDemand("passive-panel", false)
      return
    }
    // Avoid hitting interactive-state while collapsed and not in the stream (reduces 404/log churn when status is briefly stale after a stream ends).
    const needsPassivePoll =
      broadcast.isWatching || broadcast.speakInviteNotice != null

    if (!needsPassivePoll) {
      setBroadcastPassiveInteractiveContext(null)
      setBroadcastInteractivePollDemand("passive-panel", false)
      return
    }

    setBroadcastPassiveInteractiveContext({ roomId, viewerUserId })
    setBroadcastInteractivePollDemand("passive-panel", true, accessToken)
    return () => {
      setBroadcastInteractivePollDemand("passive-panel", false)
      setBroadcastPassiveInteractiveContext(null)
    }
  }, [
    accessToken,
    viewerUserId,
    roomId,
    broadcast.status.live,
    publicLive,
    broadcast.isPublishing,
    broadcast.isWatching,
    broadcast.speakInviteNotice,
  ])

  useEffect(() => {
    const wantsHostPoll =
      Boolean(accessToken) && broadcast.isPublishing && publicLive
    setBroadcastInteractivePollDemand("host-studio", wantsHostPoll, accessToken)
    return () => setBroadcastInteractivePollDemand("host-studio", false)
  }, [accessToken, broadcast.isPublishing, publicLive, roomId])

  const onWatchStream = useCallback(() => {
    if (!accessToken || !publicLive || broadcast.isPublishing) return
    void openTradeRoomBroadcastViewerStudio({
      roomId,
      accessToken,
      viewerUserId,
    })
  }, [accessToken, publicLive, broadcast.isPublishing, roomId, viewerUserId])

  const onManageStream = useCallback(() => {
    openTradeRoomBroadcastHostStudio()
  }, [])

  const onLeaveStream = useCallback(async () => {
    await leaveTradeRoomBroadcastViewer()
    setTradeRoomBroadcastStudioPresentation("hidden")
  }, [])

  useEffect(() => {
    if (!broadcast.isPublishing || !obsPrivateSetupExpanded) return
    const el = videoRef.current
    if (!el) return
    syncTradeRoomBroadcastLocalPreviewElement(el)
  }, [
    broadcast.isPublishing,
    obsPrivateSetupExpanded,
    broadcast.connectionState,
    broadcast.status.videoSource,
  ])

  const ownerLiveElsewhere =
    Boolean(broadcast.status.alreadyLiveElsewhere) &&
    !broadcast.isPublishing &&
    viewerUserId != null &&
    broadcast.status.broadcasterUserId === viewerUserId
  const viewerCount =
    broadcast.localViewerCount > 0
      ? broadcast.localViewerCount
      : (broadcast.status.viewerCount ?? 0)

  const broadcasterLabel =
    broadcast.status.broadcasterDisplayName?.trim() || "Broadcaster"

  useEffect(() => {
    logBroadcast("broadcast panel render state", {
      sessionIdTail: broadcast.status.broadcastSessionId?.slice(-8) ?? null,
      videoSource: broadcast.status.videoSource ?? null,
      broadcastSource: broadcast.status.broadcastSource ?? null,
      visibility: broadcast.status.visibility ?? null,
      publicLive,
      storePublicLive: broadcast.status.publicLive ?? null,
      isPublishing: broadcast.isPublishing,
      obsBootstrap: broadcast.obsBroadcastBootstrapping,
      obsHostUiPhase: broadcast.obsHostUiPhase ?? null,
      obsPreparingHost,
      obsPrivateSetupExpanded,
      connectionState: broadcast.connectionState,
    })
  }, [
    broadcast.status.broadcastSessionId,
    broadcast.status.videoSource,
    broadcast.status.broadcastSource,
    broadcast.status.visibility,
    broadcast.status.publicLive,
    broadcast.isPublishing,
    broadcast.obsBroadcastBootstrapping,
    broadcast.obsHostUiPhase,
    broadcast.connectionState,
    obsPreparingHost,
    obsPrivateSetupExpanded,
    publicLive,
  ])

  const showPanel =
    isLive ||
    canGoLive ||
    broadcast.isBusy ||
    broadcast.isPublishing ||
    obsPreparingHost ||
    broadcast.obsBroadcastBootstrapping
  if (!showPanel) {
    return null
  }

  return (
    <>
      <TradeRoomBroadcastGoLiveDialog
        open={goLiveOpen}
        onClose={() => setGoLiveOpen(false)}
        onConfirm={(r) => void runGoLive(r)}
        busy={broadcast.isBusy}
      />

      <div className="shrink-0 border-b border-white/10 bg-black/40 px-3 py-2 md:px-4">
        <div className="flex flex-wrap items-center gap-2">
          {obsHostPrivatePrepChrome ? (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-violet-500/20 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-violet-200">
              Preparing OBS
            </span>
          ) : publicLive ? (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-red-500/20 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-red-300">
              <Radio className="h-3.5 w-3.5" aria-hidden />
              Live
            </span>
          ) : null}
          {obsHostPrivatePrepChrome ? (
            <span className="truncate text-sm text-gray-200">
              Private setup — viewers won&apos;t see this until you tap{" "}
              <span className="font-semibold text-white">Go live</span>
            </span>
          ) : publicLive ? (
            <span className="truncate text-sm text-gray-200">
              {broadcasterLabel}
              {viewerCount != null ? (
                <span className="text-gray-500"> · {viewerCount} watching</span>
              ) : null}
            </span>
          ) : (
            <span className="text-sm text-gray-400">No live stream</span>
          )}

          <div className="ml-auto flex flex-wrap items-center gap-2">
            {ownerLiveElsewhere ? (
              <>
                <span className="text-xs text-amber-200">
                  Already live in another tab or device
                </span>
                <button
                  type="button"
                  disabled={broadcast.isBusy || !accessToken}
                  onClick={() => void onStopLive()}
                  className="rounded-lg border border-red-400/40 px-3 py-1.5 text-xs font-semibold text-red-200 hover:bg-red-500/10"
                >
                  End stream
                </button>
              </>
            ) : null}
            {canGoLive &&
            !broadcast.isPublishing &&
            !broadcast.obsBroadcastBootstrapping &&
            !ownerLiveElsewhere ? (
              <button
                type="button"
                disabled={tradeRoomGoLiveButtonDisabled({
                  isBusy: broadcast.isBusy,
                  accessTokenPresent: Boolean(accessToken),
                  publicLive,
                })}
                onClick={() => setGoLiveOpen(true)}
                className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500 disabled:opacity-50"
              >
                Go Live
              </button>
            ) : null}
            {broadcast.isPublishing ? (
              <>
                {!obsPreparingHost ? (
                  <button
                    type="button"
                    disabled={broadcast.isBusy}
                    onClick={() => void toggleTradeRoomBroadcastMicMuted()}
                    className="rounded-lg border border-white/15 p-1.5 text-gray-200 hover:bg-white/5"
                    aria-label={
                      broadcast.broadcasterMicMuted ? "Unmute mic" : "Mute mic"
                    }
                  >
                    {broadcast.broadcasterMicMuted ? (
                      <MicOff className="h-4 w-4" />
                    ) : (
                      <Mic className="h-4 w-4" />
                    )}
                  </button>
                ) : null}
                <button
                  type="button"
                  disabled={broadcast.isBusy}
                  onClick={() => void onStopLive()}
                  className="rounded-lg border border-red-400/40 px-3 py-1.5 text-xs font-semibold text-red-200 hover:bg-red-500/10"
                >
                  {obsPreparingHost ? "Cancel setup" : "Stop stream"}
                </button>
                {obsPreparingHost && accessToken ? (
                  <button
                    type="button"
                    disabled={!obsReadyForPublic}
                    onClick={() =>
                      void publishTradeRoomBroadcastObs({
                        roomId,
                        accessToken,
                      })
                    }
                    title={
                      !obsReadyForPublic
                        ? "Start streaming in OBS and wait for preview"
                        : undefined
                    }
                    className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-500 disabled:opacity-50"
                  >
                    Go live to room
                  </button>
                ) : null}
              </>
            ) : null}
            {publicLive && broadcast.isPublishing && !obsPreparingHost ? (
              <button
                type="button"
                onClick={onManageStream}
                className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-600"
              >
                Manage stream
              </button>
            ) : null}
            {publicLive && !broadcast.isPublishing ? (
              <>
                <button
                  type="button"
                  disabled={broadcast.isBusy || !accessToken}
                  onClick={onWatchStream}
                  className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-600 disabled:opacity-50"
                >
                  {broadcast.isWatching
                    ? broadcast.studioPresentation === "studio"
                      ? "Return to studio"
                      : "Open studio"
                    : "Watch stream"}
                </button>
                {broadcast.isWatching ? (
                  <button
                    type="button"
                    disabled={broadcast.isBusy}
                    onClick={() => void onLeaveStream()}
                    className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-gray-200 hover:bg-white/5 disabled:opacity-50"
                  >
                    Leave stream
                  </button>
                ) : null}
              </>
            ) : null}
          </div>
        </div>

        {broadcast.speakInviteNotice &&
        publicLive &&
        !broadcast.isPublishing &&
        !broadcast.isInConversation &&
        !broadcast.isWatching ? (
          <p className="mt-2 text-xs text-emerald-200">
            You&apos;re invited to speak — tap <span className="font-semibold">Watch stream</span>{" "}
            to open the studio and accept.
          </p>
        ) : null}

        {broadcast.viewerBroadcastConnectionLost ? (
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <p className="text-xs text-amber-200">
              Connection lost. You can try watching again.
            </p>
            <button
              type="button"
              disabled={broadcast.isBusy || !accessToken}
              className="rounded-lg border border-amber-400/40 px-2.5 py-1 text-xs font-semibold text-amber-100 hover:bg-amber-500/10 disabled:opacity-50"
              onClick={() => {
                acknowledgeViewerBroadcastConnectionLost()
                onWatchStream()
              }}
            >
              Retry
            </button>
          </div>
        ) : null}
        {broadcast.error ? (
          <p className="mt-2 text-xs text-red-400">{broadcast.error}</p>
        ) : null}
        {broadcast.broadcasterMicWarning ? (
          <p className="mt-2 text-xs text-amber-300">{broadcast.broadcasterMicWarning}</p>
        ) : null}
        {broadcast.generalVoiceOverlapWarning ? (
          <p className="mt-2 text-xs text-amber-300/90">
            {broadcast.generalVoiceOverlapWarning}
          </p>
        ) : null}

        {broadcast.isInConversation &&
        !broadcast.isPublishing &&
        !broadcast.viewerMicPublishReady ? (
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-amber-200">
            <span>
              {broadcast.error?.trim()
                ? broadcast.error
                : "Microphone is not publishing to the stream yet."}
            </span>
            <button
              type="button"
              disabled={broadcast.isBusy}
              className="rounded border border-amber-400/40 px-2 py-0.5 font-semibold text-amber-100 hover:bg-amber-500/10 disabled:opacity-50"
              onClick={() => void retryTradeRoomBroadcastConversationMicrophone()}
            >
              Retry mic
            </button>
          </div>
        ) : null}

        {broadcast.isPublishing ? (
          <p className="mt-2 text-xs text-emerald-300/90">
            {broadcast.status.videoSource === "obs" ? (
              obsPreparingHost ? (
                <>
                  Private setup — configure OBS with the RTMP URL and stream key below.
                  When the preview shows, tap <span className="font-semibold">Go live</span>{" "}
                  to make the stream visible in the room (no notifications until then).
                  Use <span className="font-semibold">Cancel setup</span> to revoke
                  credentials and end this session.
                </>
              ) : (
                <>
                  You are live — program video and audio come from OBS via RTMP. This
                  browser session is for preview, moderation, chat, and Invite to Talk.
                  Use <span className="font-semibold">Stop stream</span> in TradeTraxs
                  to end the broadcast and revoke streaming credentials (closing this
                  tab does not stop OBS).
                </>
              )
            ) : (
              <>
                You are live — stream audio uses this session, not General Voice.
                Stop sharing from the browser picker or tap Stop stream.
              </>
            )}
          </p>
        ) : null}

        {obsPrivateSetupExpanded ? (
          <div className="mt-3 flex min-h-[280px] flex-col gap-3">
            <div className="rounded-lg border border-violet-500/30 bg-zinc-950/80 p-4 text-sm text-gray-200">
              <p className="font-semibold text-violet-200">OBS Studio — private setup</p>
              <p className="mt-2 text-xs text-gray-400">
                Viewers cannot see this room until you tap{" "}
                <span className="font-semibold text-white">Go live to room</span> in the
                bar above. Use{" "}
                <span className="font-semibold text-white">Cancel setup</span> to revoke
                ingress and end this session.
              </p>
              {broadcast.obsBroadcastBootstrapping ? (
                <p className="mt-3 text-xs text-gray-500">
                  Connecting to TradeTraxs…
                </p>
              ) : null}
              {broadcast.obsStudio?.credentialsBusy ? (
                <p className="mt-3 text-xs text-amber-200/90">
                  Generating OBS credentials…
                </p>
              ) : null}
              {broadcast.obsStudio?.credentialsError ? (
                <div
                  className={`mt-3 space-y-2 rounded border p-3 text-xs ${
                    broadcast.obsStudio.credentialsLostOrUnavailable
                      ? "border-amber-400/35 bg-amber-950/35"
                      : "border-red-400/30 bg-red-950/40"
                  }`}
                >
                  <p
                    className={
                      broadcast.obsStudio.credentialsLostOrUnavailable
                        ? "text-amber-100/95"
                        : "text-red-200"
                    }
                  >
                    {broadcast.obsStudio.credentialsError}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={broadcast.isBusy || broadcast.obsStudio.credentialsBusy}
                      onClick={() => void retryObsCredentials()}
                      className="rounded border border-white/20 px-2 py-1 text-xs font-semibold text-white hover:bg-white/10 disabled:opacity-50"
                    >
                      {broadcast.obsStudio.credentialsLostOrUnavailable
                        ? "Try again"
                        : "Retry"}
                    </button>
                    <button
                      type="button"
                      disabled={broadcast.isBusy || broadcast.obsStudio.credentialsBusy}
                      onClick={() => void regenerateObsCredentials()}
                      className="rounded border border-amber-400/40 px-2 py-1 text-xs font-semibold text-amber-100 hover:bg-amber-500/10 disabled:opacity-50"
                    >
                      Regenerate stream key
                    </button>
                  </div>
                </div>
              ) : null}
              {broadcast.obsStudio?.rtmpUrl ? (
                <div className="mt-4 space-y-3 text-xs">
                  <p className="text-gray-400">
                    In OBS: <span className="text-gray-300">Settings → Stream</span>.
                    Set <span className="text-gray-300">Service</span> to{" "}
                    <span className="text-gray-300">Custom...</span>. Paste the server
                    URL and stream key, then click{" "}
                    <span className="text-gray-300">Start Streaming</span> in OBS.
                  </p>
                  <div className="space-y-1">
                    <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                      Server (RTMP URL)
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                      <code className="max-w-full flex-1 break-all rounded bg-black/50 px-2 py-1 text-[11px] text-violet-200">
                        {broadcast.obsStudio.rtmpUrl}
                      </code>
                      <button
                        type="button"
                        className="inline-flex shrink-0 items-center gap-1 rounded border border-white/15 px-2 py-1 text-[11px] hover:bg-white/5"
                        onClick={() =>
                          void copyObsFieldToClipboard(broadcast.obsStudio!.rtmpUrl!)
                        }
                      >
                        <Copy className="h-3 w-3" aria-hidden />
                        Copy
                      </button>
                    </div>
                  </div>
                  <div className="space-y-1">
                    <div className="flex flex-wrap items-center gap-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                      <span>Stream key</span>
                      <button
                        type="button"
                        className="inline-flex items-center gap-1 rounded border border-white/10 px-2 py-0.5 normal-case text-gray-300 hover:bg-white/5"
                        onClick={() =>
                          setObsStreamKeyRevealed(
                            !broadcast.obsStudio?.revealedStreamKey
                          )
                        }
                      >
                        {broadcast.obsStudio?.revealedStreamKey ? (
                          <>
                            <EyeOff className="h-3 w-3" /> Hide
                          </>
                        ) : (
                          <>
                            <Eye className="h-3 w-3" /> Show
                          </>
                        )}
                      </button>
                    </div>
                    {broadcast.obsStudio.revealedStreamKey ? (
                      <div className="flex flex-wrap items-center gap-2">
                        <code className="max-w-full flex-1 break-all rounded bg-black/50 px-2 py-1 text-[11px] text-amber-100">
                          {broadcast.obsStudio.revealedStreamKey}
                        </code>
                        <button
                          type="button"
                          className="inline-flex shrink-0 items-center gap-1 rounded border border-white/15 px-2 py-1 text-[11px] hover:bg-white/5"
                          onClick={() =>
                            void copyObsFieldToClipboard(
                              broadcast.obsStudio!.revealedStreamKey!
                            )
                          }
                        >
                          <Copy className="h-3 w-3" aria-hidden />
                          Copy
                        </button>
                      </div>
                    ) : (
                      <p className="text-gray-500">
                        Hidden — click Show to reveal. Do not share this key outside
                        OBS.
                      </p>
                    )}
                  </div>
                </div>
              ) : !broadcast.obsStudio?.credentialsBusy &&
                !broadcast.obsBroadcastBootstrapping &&
                !broadcast.obsStudio?.credentialsError ? (
                <p className="mt-3 text-xs text-gray-500">
                  Waiting for streaming credentials…
                </p>
              ) : null}
            </div>

            <div
              className={`text-xs ${
                encoderConnected
                  ? "font-medium text-emerald-300/90"
                  : "text-amber-200/90"
              }`}
            >
              {encoderConnected
                ? "OBS connected — private preview below."
                : waitingForObsEncoder
                  ? "Waiting for OBS — start streaming in OBS with the credentials above."
                  : "Waiting for OBS encoder…"}
            </div>

            <div
              ref={containerRef}
              className="relative min-h-[220px] w-full overflow-hidden rounded-lg border border-white/10 bg-black aspect-video lg:min-h-[320px]"
            >
              {broadcast.isPublishing && broadcast.broadcasterPreviewError ? (
                <div className="absolute inset-0 z-10 flex items-center justify-center bg-black/80 px-4 text-center text-sm text-amber-200">
                  {broadcast.broadcasterPreviewError}
                </div>
              ) : null}
              {!encoderConnected && obsPreparingHost ? (
                <div className="pointer-events-none absolute inset-0 z-[5] flex items-center justify-center bg-black/70 px-4 text-center text-sm text-gray-300">
                  No preview yet — connect OBS to see your program feed here (private).
                </div>
              ) : null}
              <video
                ref={bindStreamVideoRef}
                className="h-full w-full object-contain"
                playsInline
                muted
                autoPlay
              />
            </div>
          </div>
        ) : null}
      </div>
    </>
  )
}
