import {
  Room,
  RoomEvent,
  Track,
  type LocalTrackPublication,
  type LocalVideoTrack,
} from "livekit-client"
import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"
import {
  isBroadcastDiagnosticsEnabled,
  logBroadcast,
  logBroadcastVideoElementHealth,
} from "./tradeRoomBroadcastDiagnostics.ts"

let attachedLocalTrackKey: string | null = null
let attachedPreviewElement: HTMLVideoElement | null = null

/** Stable per-session key — `track.sid` is assigned after publish and must not toggle detach logic. */
export function localBroadcastPreviewTrackKey(track: LocalVideoTrack): string {
  return track.mediaStreamTrack.id
}

export function findLocalBroadcastVideoPublication(
  room: Room,
  preferredSource: TradeRoomBroadcastVideoSource
): LocalTrackPublication | undefined {
  const pubs = [...room.localParticipant.videoTrackPublications.values()]
  const preferScreen = preferredSource === "screen"

  const isScreenPub = (source: Track.Source) =>
    source === Track.Source.ScreenShare ||
    source === Track.Source.ScreenShareAudio

  if (preferScreen) {
    const screen = pubs.find((p) => isScreenPub(p.source))
    if (screen?.track) return screen
  } else {
    const camera = pubs.find((p) => p.source === Track.Source.Camera)
    if (camera?.track) return camera
  }

  return pubs.find((p) => p.track != null)
}

/** Published program track for the browser host (screen compositor when live, else camera). */
export function findLocalBroadcastProgramVideoPublication(
  room: Room
): LocalTrackPublication | undefined {
  const screen = findLocalBroadcastVideoPublication(room, "screen")
  const screenTrack = screen?.track ?? screen?.videoTrack
  const screenMedia = screenTrack?.mediaStreamTrack
  if (screenMedia && screenMedia.readyState === "live") {
    return screen
  }
  return findLocalBroadcastVideoPublication(room, "camera")
}

export function attachLocalBroadcastVideoTrack(
  track: LocalVideoTrack,
  videoEl: HTMLVideoElement
): void {
  const trackKey = localBroadcastPreviewTrackKey(track)
  const publishedSid = track.sid ?? null
  if (attachedLocalTrackKey === trackKey && attachedPreviewElement === videoEl) {
    void videoEl.play().catch(() => {})
    return
  }

  /**
   * Broadcaster may sync the same local camera/screen track to multiple `<video>` nodes
   * (e.g. Trade Room panel + global studio). LiveKit supports multi-attach; detaching from
   * the previous element would clear `srcObject` there and leave a black preview.
   */
  const sameTrackAsLastAttach =
    attachedLocalTrackKey != null && attachedLocalTrackKey === trackKey

  if (attachedPreviewElement && attachedPreviewElement !== videoEl && !sameTrackAsLastAttach) {
    try {
      track.detach(attachedPreviewElement)
    } catch {
      // ignore stale detach
    }
  }

  track.attach(videoEl)
  videoEl.muted = true
  videoEl.playsInline = true
  videoEl.autoplay = true

  attachedLocalTrackKey = trackKey
  attachedPreviewElement = videoEl

  logBroadcast("local preview attached", {
    trackKey,
    publishedSid,
    trackSource: track.source?.toString?.() ?? String(track.source),
  })

  void videoEl.play().then(
    () => logBroadcastVideoElementHealth("local preview after play()", videoEl),
    (err) => {
      logBroadcast("local preview play() rejected", {
        message: err instanceof Error ? err.message : String(err),
      })
      logBroadcastVideoElementHealth("local preview play failed", videoEl)
    }
  )
}

export function detachLocalBroadcastPreview(): void {
  attachedLocalTrackKey = null
  attachedPreviewElement = null
}

export function syncLocalBroadcastPreviewToElement(
  room: Room,
  videoEl: HTMLVideoElement,
  preferredSource?: TradeRoomBroadcastVideoSource
): { ok: true } | { ok: false; reason: string } {
  const pub = preferredSource
    ? findLocalBroadcastVideoPublication(room, preferredSource)
    : findLocalBroadcastProgramVideoPublication(room)
  const track = pub?.videoTrack ?? (pub?.track as LocalVideoTrack | undefined)
  if (!track) {
    logBroadcast("local preview sync — no published local video track", {
      preferredSource: preferredSource ?? "program",
      publicationCount: room.localParticipant.videoTrackPublications.size,
      publicationSources: [...room.localParticipant.videoTrackPublications.values()].map(
        (p) => ({
          source: String(p.source),
          hasTrack: Boolean(p.track),
        })
      ),
    })
    return { ok: false, reason: "No local video track is published yet." }
  }

  attachLocalBroadcastVideoTrack(track, videoEl)
  if (isBroadcastDiagnosticsEnabled()) {
    logBroadcastVideoElementHealth(
      `local preview sync (${preferredSource ?? "program"})`,
      videoEl
    )
  }
  return { ok: true }
}

export function registerLocalBroadcastPreviewHandlers(
  room: Room,
  getVideoElement: () => HTMLVideoElement | null,
  preferredSource?: TradeRoomBroadcastVideoSource
): () => void {
  const resync = () => {
    const el = getVideoElement()
    if (!el) return
    syncLocalBroadcastPreviewToElement(room, el, preferredSource)
  }

  room.on(RoomEvent.LocalTrackPublished, resync)
  room.on(RoomEvent.LocalTrackUnpublished, resync)
  resync()

  return () => {
    room.off(RoomEvent.LocalTrackPublished, resync)
    room.off(RoomEvent.LocalTrackUnpublished, resync)
    detachLocalBroadcastPreview()
  }
}
