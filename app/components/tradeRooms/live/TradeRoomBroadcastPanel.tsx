"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { ConnectionState } from "livekit-client"
import { Maximize2, Mic, MicOff, Radio, Volume2, VolumeX, X } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastGoLiveDialog, {
  type GoLiveDialogResult,
} from "./TradeRoomBroadcastGoLiveDialog.tsx"
import TradeRoomBroadcastLiveChat from "./TradeRoomBroadcastLiveChat.tsx"
import TradeRoomBroadcastSpeakInviteBanner from "./TradeRoomBroadcastSpeakInviteBanner.tsx"
import TradeRoomBroadcastHostSidebar from "./TradeRoomBroadcastHostSidebar.tsx"
import {
  refreshBroadcastInteractiveState,
  sendTradeRoomBroadcastChatMessage,
  setBroadcastPassiveInteractiveContext,
  joinTradeRoomBroadcastConversation,
  leaveTradeRoomBroadcastConversation,
  leaveTradeRoomBroadcastViewer,
  refreshTradeRoomBroadcastStatus,
  startTradeRoomBroadcast,
  setTradeRoomBroadcastRoomTitle,
  setTradeRoomBroadcastStudioPresentation,
  stopTradeRoomBroadcast,
  syncTradeRoomBroadcastLocalPreviewElement,
  syncTradeRoomBroadcastViewerVideoElement,
  toggleTradeRoomBroadcastMicMuted,
  toggleTradeRoomBroadcastStreamListenMuted,
  toggleTradeRoomBroadcastViewerMicMuted,
  toggleTradeRoomBroadcastRaisedHand,
  watchTradeRoomBroadcast,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { logBroadcast } from "@/lib/livekit/client/tradeRoomBroadcastDiagnostics.ts"
import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "@/lib/livekit/tradeRoomBroadcastVoiceMode.ts"

type Props = {
  roomId: string
  roomTitle?: string
  canGoLive: boolean
  accessToken: string | null
  viewerUserId: string | null
  viewerDisplayName: string
  viewerAvatarUrl: string | null
  expanded: boolean
  onExpandedChange: (open: boolean) => void
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
  broadcastSessionId?: string
  broadcasterUserId?: string
  broadcasterDisplayName?: string | null
  startedAt?: string
  viewerCount?: number | null
  voiceMode?: TradeRoomBroadcastVoiceMode
  videoSource?: TradeRoomBroadcastVideoSource
  broadcasterConnected?: boolean | null
  alreadyLiveElsewhere?: boolean
  error?: string
}

type TokenPayload = StatusPayload & {
  token?: string
  livekitUrl?: string
}

export default function TradeRoomBroadcastPanel({
  roomId,
  roomTitle,
  canGoLive,
  accessToken,
  viewerUserId,
  viewerDisplayName,
  viewerAvatarUrl,
  expanded,
  onExpandedChange,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const videoRef = useRef<HTMLVideoElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [goLiveOpen, setGoLiveOpen] = useState(false)

  const bindStreamVideoRef = useCallback(
    (el: HTMLVideoElement | null) => {
      ;(videoRef as React.MutableRefObject<HTMLVideoElement | null>).current = el
      if (!el) return
      if (broadcast.isPublishing) {
        syncTradeRoomBroadcastLocalPreviewElement(el)
      } else {
        syncTradeRoomBroadcastViewerVideoElement(el)
      }
    },
    [broadcast.isPublishing]
  )

  const fetchStatus = useCallback(async () => {
    if (!accessToken) {
      return { live: false }
    }
    const reconcileQuery = canGoLive ? "&reconcile=1" : ""
    const res = await authFetch(
      accessToken,
      `/api/livekit/broadcast/status?roomId=${encodeURIComponent(roomId)}${reconcileQuery}`
    )
    const payload = (await res.json().catch(() => ({}))) as StatusPayload
    logBroadcast("status API response", {
      roomId,
      httpStatus: res.status,
      live: payload.live ?? null,
      broadcastSessionId: payload.broadcastSessionId ?? null,
      videoSource: payload.videoSource ?? null,
    })
    if (!res.ok) {
      throw new Error(payload.error || "Could not load stream status.")
    }
    return {
      live: Boolean(payload.live),
      broadcastSessionId: payload.broadcastSessionId,
      broadcasterUserId: payload.broadcasterUserId,
      broadcasterDisplayName: payload.broadcasterDisplayName,
      startedAt: payload.startedAt,
      viewerCount: payload.viewerCount,
      voiceMode: payload.voiceMode,
      videoSource: payload.videoSource,
      broadcasterConnected: payload.broadcasterConnected,
      alreadyLiveElsewhere: payload.alreadyLiveElsewhere,
    }
  }, [accessToken, roomId, canGoLive])

  useEffect(() => {
    if (!accessToken || !roomId) return
    void refreshTradeRoomBroadcastStatus(fetchStatus)
    const id = window.setInterval(() => {
      void refreshTradeRoomBroadcastStatus(fetchStatus)
    }, 12_000)
    return () => window.clearInterval(id)
  }, [accessToken, roomId, fetchStatus])

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
    }
  }

  const runGoLive = useCallback(
    async (setup: GoLiveDialogResult) => {
      if (!accessToken) return
      setGoLiveOpen(false)
      onExpandedChange(true)
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
    [accessToken, roomId, fetchStop, onExpandedChange]
  )

  const onStopLive = useCallback(async () => {
    const sessionId = broadcast.status.broadcastSessionId
    if (!sessionId) return
    await stopTradeRoomBroadcast({
      roomId,
      sessionId,
      fetchStop: () => fetchStop(sessionId),
    })
    void refreshTradeRoomBroadcastStatus(fetchStatus)
  }, [broadcast.status.broadcastSessionId, roomId, fetchStop, fetchStatus])

  useEffect(() => {
    if (!broadcast.viewerStreamRemovalNotice) return
    onExpandedChange(false)
  }, [broadcast.viewerStreamRemovalNotice, onExpandedChange])

  useEffect(() => {
    if (
      !broadcast.speakInviteNotice ||
      broadcast.isPublishing ||
      broadcast.isInConversation
    ) {
      return
    }
    if (!expanded) {
      onExpandedChange(true)
    }
  }, [
    broadcast.speakInviteNotice,
    broadcast.isPublishing,
    broadcast.isInConversation,
    expanded,
    onExpandedChange,
  ])

  useEffect(() => {
    if (
      !accessToken ||
      !viewerUserId ||
      !broadcast.status.live ||
      broadcast.isPublishing
    ) {
      setBroadcastPassiveInteractiveContext(null)
      return
    }
    setBroadcastPassiveInteractiveContext({ roomId, viewerUserId })
    void refreshBroadcastInteractiveState(accessToken)
    const id = window.setInterval(() => {
      void refreshBroadcastInteractiveState(accessToken)
    }, 3000)
    return () => {
      window.clearInterval(id)
      setBroadcastPassiveInteractiveContext(null)
    }
  }, [
    accessToken,
    viewerUserId,
    roomId,
    broadcast.status.live,
    broadcast.isPublishing,
  ])

  useEffect(() => {
    if (!accessToken || !broadcast.isPublishing || !expanded) return
    void refreshBroadcastInteractiveState(accessToken)
    const id = window.setInterval(() => {
      void refreshBroadcastInteractiveState(accessToken)
    }, 4000)
    return () => window.clearInterval(id)
  }, [accessToken, broadcast.isPublishing, expanded, roomId])

  useEffect(() => {
    if (!expanded || !broadcast.status.live || !accessToken) return
    if (broadcast.isPublishing) return
    const el = videoRef.current
    if (!el) return

    void watchTradeRoomBroadcast({
      roomId,
      videoElement: el,
      accessToken,
      viewerUserId,
      fetchViewerToken: async () => {
        const res = await authFetch(accessToken, "/api/livekit/broadcast/token", {
          method: "POST",
          body: JSON.stringify({ roomId }),
        })
        const payload = (await res.json().catch(() => ({}))) as TokenPayload
        if (!res.ok) {
          throw new Error(payload.error || "Could not join the stream.")
        }
        return parseTokenResponse(payload)
      },
    })
  }, [expanded, broadcast.status.live, broadcast.isPublishing, accessToken, roomId, viewerUserId])

  useEffect(() => {
    if (!broadcast.isPublishing || !expanded) return
    const el = videoRef.current
    if (!el) return
    syncTradeRoomBroadcastLocalPreviewElement(el)
  }, [
    broadcast.isPublishing,
    broadcast.connectionState,
    expanded,
    broadcast.status.videoSource,
  ])

  const onCloseViewer = useCallback(async () => {
    onExpandedChange(false)
    await leaveTradeRoomBroadcastViewer()
  }, [onExpandedChange])

  const onFullscreen = useCallback(() => {
    const target = containerRef.current
    if (!target) return
    void target.requestFullscreen?.()
  }, [])

  const onJoinConversation = useCallback(async () => {
    const el = videoRef.current
    if (!accessToken || !el) return
    await joinTradeRoomBroadcastConversation({
      roomId,
      videoElement: el,
      fetchJoin: async () => {
        const res = await authFetch(
          accessToken,
          "/api/livekit/broadcast/join-conversation",
          { method: "POST", body: JSON.stringify({ roomId }) }
        )
        const payload = (await res.json().catch(() => ({}))) as TokenPayload
        if (!res.ok) {
          throw new Error(payload.error || "Could not join conversation.")
        }
        return parseTokenResponse(payload)
      },
    })
  }, [accessToken, roomId])

  const onLeaveConversation = useCallback(async () => {
    const el = videoRef.current
    if (!accessToken || !el) return
    await leaveTradeRoomBroadcastConversation({
      roomId,
      videoElement: el,
      fetchLeave: async () => {
        const res = await authFetch(
          accessToken,
          "/api/livekit/broadcast/leave-conversation",
          { method: "POST", body: JSON.stringify({ roomId }) }
        )
        const payload = (await res.json().catch(() => ({}))) as {
          error?: string
          viewerToken?: TokenPayload | null
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
                voiceMode: vt.voiceMode,
                videoSource: vt.videoSource,
              }
            : null,
        }
      },
    })
  }, [accessToken, roomId])

  const isLive = broadcast.status.live
  const ownerLiveElsewhere =
    Boolean(broadcast.status.alreadyLiveElsewhere) &&
    !broadcast.isPublishing &&
    viewerUserId != null &&
    broadcast.status.broadcasterUserId === viewerUserId
  const isConnected =
    broadcast.connectionState === ConnectionState.Connected ||
    broadcast.connectionState === ConnectionState.Reconnecting

  const viewerCount =
    broadcast.localViewerCount > 0
      ? broadcast.localViewerCount
      : (broadcast.status.viewerCount ?? 0)

  const broadcasterLabel =
    broadcast.status.broadcasterDisplayName?.trim() || "Broadcaster"

  const showPanel = isLive || canGoLive || broadcast.isBusy || broadcast.isPublishing
  if (!showPanel) {
    return null
  }

  const showStreamChrome = expanded && (isLive || broadcast.isPublishing)
  const openVoice =
    broadcast.status.voiceMode === "open_voice" && !broadcast.isPublishing

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
          {isLive ? (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-red-500/20 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-red-300">
              <Radio className="h-3.5 w-3.5" aria-hidden />
              Live
            </span>
          ) : null}
          {isLive ? (
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
            {canGoLive && !broadcast.isPublishing && !ownerLiveElsewhere ? (
              <button
                type="button"
                disabled={broadcast.isBusy || !accessToken || isLive}
                onClick={() => setGoLiveOpen(true)}
                className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500 disabled:opacity-50"
              >
                Go Live
              </button>
            ) : null}
            {broadcast.isPublishing ? (
              <>
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
                <button
                  type="button"
                  disabled={broadcast.isBusy}
                  onClick={() => void onStopLive()}
                  className="rounded-lg border border-red-400/40 px-3 py-1.5 text-xs font-semibold text-red-200 hover:bg-red-500/10"
                >
                  Stop stream
                </button>
              </>
            ) : null}
            {isLive && !broadcast.isPublishing ? (
              <button
                type="button"
                onClick={() => onExpandedChange(!expanded)}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-gray-200 hover:bg-white/5"
              >
                {expanded ? "Hide stream" : "Watch stream"}
              </button>
            ) : null}
          </div>
        </div>

        {broadcast.speakInviteNotice &&
        accessToken &&
        !broadcast.isPublishing &&
        !broadcast.isInConversation ? (
          <TradeRoomBroadcastSpeakInviteBanner
            roomId={roomId}
            accessToken={accessToken}
            busy={broadcast.isBusy || broadcast.speakerUpgradeInFlight}
            onNeedOpenStream={() => onExpandedChange(true)}
          />
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

        {broadcast.isPublishing ? (
          <p className="mt-2 text-xs text-emerald-300/90">
            You are live — stream audio uses this session, not General Voice. Stop
            sharing from the browser picker or tap Stop stream.
          </p>
        ) : null}

        {showStreamChrome ? (
          <div className="mt-3 flex min-h-[280px] flex-col gap-3 lg:min-h-[360px] lg:flex-row lg:items-stretch">
            <div className="flex min-h-0 flex-1 flex-col lg:min-w-0 lg:flex-[1.4]">
            {broadcast.isPublishing ? (
              <div className="mb-2 flex items-center gap-3">
                <div className="flex min-w-0 flex-wrap items-center gap-3 text-xs text-gray-400">
                  <span>
                    {broadcast.connectionState === ConnectionState.Connected
                      ? "Connected"
                      : broadcast.connectionState}
                  </span>
                  <span className="inline-flex items-center gap-1 text-amber-300/90">
                    {broadcast.raisedHandIdentities.length} hand
                    {broadcast.raisedHandIdentities.length === 1 ? "" : "s"} raised
                  </span>
                </div>
                <div className="ml-auto flex shrink-0 flex-wrap items-center justify-end gap-2">
                  <button
                    type="button"
                    disabled={broadcast.isBusy}
                    onClick={() => void toggleTradeRoomBroadcastMicMuted()}
                    className="inline-flex items-center gap-2 rounded-lg border border-white/15 px-3 py-1.5 text-xs text-gray-200"
                  >
                    {broadcast.broadcasterMicMuted ? (
                      <MicOff className="h-4 w-4" />
                    ) : (
                      <Mic className="h-4 w-4" />
                    )}
                    {broadcast.broadcasterMicMuted ? "Mic off" : "Mic on"}
                  </button>
                  <button
                    type="button"
                    disabled={broadcast.isBusy}
                    onClick={() => void onStopLive()}
                    className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500"
                  >
                    End stream
                  </button>
                  <button
                    type="button"
                    className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-gray-200"
                    onClick={() => setTradeRoomBroadcastStudioPresentation("studio")}
                  >
                    Open studio
                  </button>
                </div>
              </div>
            ) : null}
            <div
              ref={containerRef}
              className="relative min-h-0 w-full flex-1 overflow-hidden rounded-lg border border-white/10 bg-black aspect-video lg:aspect-auto lg:min-h-[240px]"
            >
              {!isConnected && broadcast.isWatching ? (
                <div className="absolute inset-0 flex items-center justify-center text-sm text-gray-400">
                  Connecting to stream…
                </div>
              ) : null}
              {broadcast.isPublishing && broadcast.broadcasterPreviewError ? (
                <div className="absolute inset-0 flex items-center justify-center bg-black/80 px-4 text-center text-sm text-amber-200">
                  {broadcast.broadcasterPreviewError}
                </div>
              ) : null}
              <video
                ref={bindStreamVideoRef}
                className="h-full w-full object-contain"
                playsInline
                muted
                autoPlay
              />
              <div className="absolute right-2 top-2 flex gap-1">
                {!broadcast.isPublishing && broadcast.isWatching ? (
                  <>
                    <button
                      type="button"
                      aria-label={
                        broadcast.isInConversation
                          ? broadcast.viewerMicMuted
                            ? "Unmute your mic"
                            : "Mute your mic"
                          : broadcast.streamListenMuted
                            ? "Unmute stream"
                            : "Mute stream"
                      }
                      onClick={() => {
                        if (broadcast.isInConversation) {
                          void toggleTradeRoomBroadcastViewerMicMuted()
                        } else {
                          toggleTradeRoomBroadcastStreamListenMuted()
                        }
                      }}
                      className="rounded-md bg-black/60 p-2 text-white hover:bg-black/80"
                    >
                      {broadcast.isInConversation ? (
                        broadcast.viewerMicMuted ? (
                          <MicOff className="h-4 w-4" />
                        ) : (
                          <Mic className="h-4 w-4" />
                        )
                      ) : broadcast.streamListenMuted ? (
                        <VolumeX className="h-4 w-4" />
                      ) : (
                        <Volume2 className="h-4 w-4" />
                      )}
                    </button>
                    {accessToken && viewerUserId ? (
                      <button
                        type="button"
                        aria-label={broadcast.localHandRaised ? "Lower hand" : "Raise hand"}
                        onClick={() =>
                          void toggleTradeRoomBroadcastRaisedHand({
                            accessToken,
                            userId: viewerUserId,
                          })
                        }
                        className={`rounded-md p-2 text-white hover:bg-black/80 ${
                          broadcast.localHandRaised ? "bg-amber-500/80" : "bg-black/60"
                        }`}
                      >
                        <span className="text-xs font-bold">✋</span>
                      </button>
                    ) : null}
                  </>
                ) : null}
                <button
                  type="button"
                  aria-label="Fullscreen"
                  onClick={onFullscreen}
                  className="rounded-md bg-black/60 p-2 text-white hover:bg-black/80"
                >
                  <Maximize2 className="h-4 w-4" />
                </button>
                {!broadcast.isPublishing ? (
                  <button
                    type="button"
                    aria-label="Close stream"
                    onClick={() => void onCloseViewer()}
                    className="rounded-md bg-black/60 p-2 text-white hover:bg-black/80"
                  >
                    <X className="h-4 w-4" />
                  </button>
                ) : null}
              </div>
            </div>
            </div>

            <div className="flex min-h-[220px] flex-col gap-2 lg:w-80 lg:shrink-0 lg:self-stretch">
              {broadcast.isPublishing && accessToken ? (
                <TradeRoomBroadcastHostSidebar
                  accessToken={accessToken}
                  className="min-h-0 flex-1"
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
              ) : (
                <>
              {openVoice && !broadcast.isInConversation ? (
                <button
                  type="button"
                  disabled={broadcast.isBusy}
                  onClick={() => void onJoinConversation()}
                  className="rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-3 py-2 text-xs font-semibold text-emerald-200"
                >
                  Join conversation
                </button>
              ) : null}
              {broadcast.isInConversation ? (
                <button
                  type="button"
                  disabled={broadcast.isBusy}
                  onClick={() => void onLeaveConversation()}
                  className="rounded-lg border border-white/15 px-3 py-2 text-xs text-gray-200"
                >
                  Leave conversation
                </button>
              ) : null}
              <TradeRoomBroadcastLiveChat
                className="min-h-0 flex-1"
                messages={broadcast.chatMessages}
                userId={viewerUserId}
                displayName={viewerDisplayName}
                avatarUrl={viewerAvatarUrl}
                disabled={!isConnected}
              />
                </>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </>
  )
}
