import { BroadcastNoActiveStreamError } from "./tradeRoomBroadcastErrors.ts"
import {
  getTradeRoomBroadcastSnapshot,
  setTradeRoomBroadcastStudioPresentation,
  watchTradeRoomBroadcast,
} from "./tradeRoomBroadcastStore.ts"

let viewerBootstrapVideo: HTMLVideoElement | null = null

/** Single off-DOM viewer attach target (panel, deep links, global chrome). */
export function getTradeRoomBroadcastViewerBootstrapVideo(): HTMLVideoElement | null {
  if (typeof document === "undefined") return null
  if (!viewerBootstrapVideo) {
    const v = document.createElement("video")
    v.setAttribute("aria-hidden", "true")
    v.setAttribute("tabindex", "-1")
    v.className = "pointer-events-none fixed h-px w-px opacity-0"
    v.muted = true
    v.playsInline = true
    v.autoplay = true
    document.body.appendChild(v)
    viewerBootstrapVideo = v
  }
  return viewerBootstrapVideo
}

export function presentTradeRoomBroadcastStudio(): void {
  setTradeRoomBroadcastStudioPresentation("studio")
}

/** Keep LiveKit connected while browsing — same idea as the voice bar minimize state. */
export function minimizeTradeRoomBroadcastStudioForBrowsing(): void {
  const snap = getTradeRoomBroadcastSnapshot()
  if (snap.studioPresentation === "studio") {
    setTradeRoomBroadcastStudioPresentation("mini")
  }
}

export async function fetchTradeRoomBroadcastViewerTokenPayload(
  accessToken: string,
  roomId: string
): Promise<{
  token: string
  livekitUrl: string
  broadcastSessionId: string
  broadcasterUserId: string
  broadcasterDisplayName: string | null
  startedAt: string
  voiceMode?: import("../tradeRoomBroadcastVoiceMode.ts").TradeRoomBroadcastVoiceMode
  videoSource?: import("../tradeRoomBroadcastVoiceMode.ts").TradeRoomBroadcastVideoSource
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
  publicLive?: boolean
  visibility?: "public" | "preparing"
}> {
  const res = await fetch("/api/livekit/broadcast/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ roomId }),
  })
  const payload = (await res.json().catch(() => ({}))) as {
    error?: string
    token?: string
    livekitUrl?: string
    broadcastSessionId?: string
    broadcasterUserId?: string
    broadcasterDisplayName?: string | null
    startedAt?: string
    voiceMode?: import("../tradeRoomBroadcastVoiceMode.ts").TradeRoomBroadcastVoiceMode
    videoSource?: import("../tradeRoomBroadcastVoiceMode.ts").TradeRoomBroadcastVideoSource
    broadcastSource?: "browser" | "obs"
    primaryMediaPublisherIdentity?: string | null
    publicLive?: boolean
    visibility?: "public" | "preparing"
  }
  if (!res.ok) {
    if (res.status === 404) {
      throw new BroadcastNoActiveStreamError(
        typeof payload.error === "string" && payload.error.trim()
          ? payload.error
          : undefined
      )
    }
    throw new Error(payload.error || "Could not join the stream.")
  }
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
    voiceMode: payload.voiceMode,
    videoSource: payload.videoSource,
    broadcastSource: payload.broadcastSource,
    primaryMediaPublisherIdentity: payload.primaryMediaPublisherIdentity,
    publicLive: payload.publicLive,
    visibility: payload.visibility,
  }
}

/**
 * Viewer path: connect (if needed) and show full studio — used by Watch stream and `?live=` links.
 */
export async function openTradeRoomBroadcastViewerStudio(options: {
  roomId: string
  accessToken: string
  viewerUserId?: string | null
}): Promise<void> {
  const snap = getTradeRoomBroadcastSnapshot()
  const alreadyWatchingThisRoom =
    snap.isWatching &&
    !snap.isPublishing &&
    snap.roomId === options.roomId &&
    (snap.role === "viewer" || snap.role === "conversation")

  if (alreadyWatchingThisRoom) {
    presentTradeRoomBroadcastStudio()
    return
  }

  const videoElement = getTradeRoomBroadcastViewerBootstrapVideo()
  if (!videoElement) return

  await watchTradeRoomBroadcast({
    roomId: options.roomId,
    videoElement,
    accessToken: options.accessToken,
    viewerUserId: options.viewerUserId ?? null,
    fetchViewerToken: () =>
      fetchTradeRoomBroadcastViewerTokenPayload(options.accessToken, options.roomId),
  })
  presentTradeRoomBroadcastStudio()
}

/** Host / moderator path: reopen full studio without tearing down the publisher session. */
export function openTradeRoomBroadcastHostStudio(): void {
  presentTradeRoomBroadcastStudio()
}
