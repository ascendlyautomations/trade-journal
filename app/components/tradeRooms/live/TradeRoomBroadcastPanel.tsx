"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { ConnectionState } from "livekit-client"
import { Mic, MicOff, Radio } from "lucide-react"
import TradeRoomObsPrivateSetupContent from "./TradeRoomObsPrivateSetupContent.tsx"
import MobileWebObsBroadcastSetupSheet from "@/app/components/mobile/tradeRooms/MobileWebObsBroadcastSetupSheet.tsx"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastGoLiveDialog, {
  type GoLiveDialogResult,
} from "./TradeRoomBroadcastGoLiveDialog.tsx"
import {
  setBroadcastInteractivePollDemand,
  setBroadcastPassiveInteractiveContext,
  setBroadcastRoomStatusPollDemand,
  fetchTradeRoomBroadcastRoomStatus,
  leaveTradeRoomBroadcastViewer,
  refreshTradeRoomBroadcastStatus,
  startTradeRoomBroadcast,
  publishTradeRoomBroadcastObs,
  setTradeRoomBroadcastRoomTitle,
  setTradeRoomBroadcastStudioPresentation,
  stopTradeRoomBroadcast,
  syncTradeRoomBroadcastLocalPreviewElement,
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
import { getSupabaseApiAccessToken } from "@/lib/supabaseBearerFetch"

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
  const phoneWeb = usePhoneWebTouchTarget()
  const [obsSetupSheetOpen, setObsSetupSheetOpen] = useState(false)
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
      if (statusAuthPausedRef.current) {
        return { live: false }
      }
      try {
        const next = await fetchTradeRoomBroadcastRoomStatus(roomId, {
          reconcile,
          lite,
          canReconcile: canGoLive,
        })
        statusAuthPausedRef.current = false
        logBroadcast("status API response", {
          roomId,
          live: next.live ?? null,
          broadcastSessionId: next.broadcastSessionId ?? null,
          videoSource: next.videoSource ?? null,
          visibility: next.visibility ?? null,
          publicLive: next.publicLive ?? null,
        })
        return next
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Could not load stream status."
        if (message.includes("Sign in required")) {
          statusAuthPausedRef.current = true
          return { live: false }
        }
        throw err
      }
    },
    [roomId, canGoLive]
  )

  const statusFetchInFlightRef = useRef(false)
  const statusAuthPausedRef = useRef(false)

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

  const inThisRoomLiveKitSession =
    broadcast.roomId === roomId &&
    (broadcast.isWatching || broadcast.isPublishing)

  useEffect(() => {
    statusAuthPausedRef.current = false
  }, [accessToken, roomId])

  /** One shared GET /status timer per room (store); skip while connected on LiveKit for this room. */
  useEffect(() => {
    if (!accessToken || !roomId || statusAuthPausedRef.current) {
      setBroadcastRoomStatusPollDemand(false)
      return
    }
    if (inThisRoomLiveKitSession && !obsPreparingHost) {
      setBroadcastRoomStatusPollDemand(false)
      return
    }
    const mode = obsPreparingHost ? "obs-prep" : "idle"
    setBroadcastRoomStatusPollDemand(true, {
      roomId,
      accessToken,
      canReconcile: canGoLive,
      mode,
    })
    return () => setBroadcastRoomStatusPollDemand(false)
  }, [
    accessToken,
    roomId,
    canGoLive,
    obsPreparingHost,
    inThisRoomLiveKitSession,
  ])

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
      const bearerToken =
        (await getSupabaseApiAccessToken()) ?? accessToken?.trim() ?? null
      if (!bearerToken) return
      setGoLiveOpen(false)
      if (phoneWeb && setup.videoSource === "obs") {
        setObsSetupSheetOpen(true)
      }
      setTradeRoomBroadcastRoomTitle(roomTitle ?? "Trade Room")
      await startTradeRoomBroadcast({
        roomId,
        setup,
        publisherAccessToken: bearerToken,
        fetchStop,
        fetchStart: async () => {
          const res = await authFetch(bearerToken, "/api/livekit/broadcast/start", {
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
    [accessToken, phoneWeb, roomId, roomTitle, fetchStop]
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
    if (broadcast.isWatching && broadcast.roomId === roomId) {
      setBroadcastPassiveInteractiveContext(null)
      setBroadcastInteractivePollDemand("passive-panel", false)
      return
    }

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

        {broadcast.viewerBroadcastConnectionLost && !phoneWeb ? (
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

        {obsPrivateSetupExpanded && phoneWeb ? (
          <div className="mt-3 md:hidden">
            <button
              type="button"
              onClick={() => setObsSetupSheetOpen(true)}
              className="w-full rounded-xl border border-violet-400/35 bg-violet-950/30 px-4 py-3 text-left text-sm font-semibold text-violet-100 hover:bg-violet-950/50"
            >
              OBS setup — RTMP &amp; stream key
            </button>
            {!obsSetupSheetOpen ? (
              <video
                ref={bindStreamVideoRef}
                className="pointer-events-none fixed h-px w-px opacity-0"
                playsInline
                muted
                autoPlay
                aria-hidden
                tabIndex={-1}
              />
            ) : null}
            <MobileWebObsBroadcastSetupSheet
              open={obsSetupSheetOpen}
              onClose={() => setObsSetupSheetOpen(false)}
            >
              <TradeRoomObsPrivateSetupContent
                videoRef={bindStreamVideoRef}
                containerRef={containerRef}
                onRetryCredentials={retryObsCredentials}
                onRegenerateCredentials={regenerateObsCredentials}
                obsPreparingHost={obsPreparingHost}
                encoderConnected={encoderConnected}
                waitingForObsEncoder={waitingForObsEncoder}
              />
            </MobileWebObsBroadcastSetupSheet>
          </div>
        ) : null}

        {obsPrivateSetupExpanded ? (
          <div className="mt-3 hidden min-h-[280px] flex-col gap-3 md:flex">
            <TradeRoomObsPrivateSetupContent
              videoRef={bindStreamVideoRef}
              containerRef={containerRef}
              onRetryCredentials={retryObsCredentials}
              onRegenerateCredentials={regenerateObsCredentials}
              obsPreparingHost={obsPreparingHost}
              encoderConnected={encoderConnected}
              waitingForObsEncoder={waitingForObsEncoder}
            />
          </div>
        ) : null}
      </div>
    </>
  )
}
