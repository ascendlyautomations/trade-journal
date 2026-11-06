import {
  Room,
  RoomEvent,
  Track,
  type LocalTrackPublication,
  type LocalVideoTrack,
} from "livekit-client"
import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"
import {
  logBroadcast,
  logBroadcastVideoElementHealth,
} from "./tradeRoomBroadcastDiagnostics.ts"

let attachedLocalTrackSid: string | null = null
let attachedPreviewElement: HTMLVideoElement | null = null

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

export function attachLocalBroadcastVideoTrack(
  track: LocalVideoTrack,
  videoEl: HTMLVideoElement
): void {
  const sid = track.sid ?? track.mediaStreamTrack.id
  if (attachedLocalTrackSid === sid && attachedPreviewElement === videoEl) {
    void videoEl.play().catch(() => {})
    return
  }

  if (attachedPreviewElement && attachedPreviewElement !== videoEl) {
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

  attachedLocalTrackSid = sid
  attachedPreviewElement = videoEl

  logBroadcast("local preview attached", {
    trackSid: sid,
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
  attachedLocalTrackSid = null
  attachedPreviewElement = null
}

export function syncLocalBroadcastPreviewToElement(
  room: Room,
  videoEl: HTMLVideoElement,
  preferredSource: TradeRoomBroadcastVideoSource
): { ok: true } | { ok: false; reason: string } {
  const pub = findLocalBroadcastVideoPublication(room, preferredSource)
  const track = pub?.videoTrack ?? (pub?.track as LocalVideoTrack | undefined)
  if (!track) {
    logBroadcast("local preview sync — no published local video track", {
      preferredSource,
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
  return { ok: true }
}

export function registerLocalBroadcastPreviewHandlers(
  room: Room,
  getVideoElement: () => HTMLVideoElement | null,
  preferredSource: TradeRoomBroadcastVideoSource
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
