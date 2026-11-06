import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type RemoteTrack,
  type RemoteTrackPublication,
} from "livekit-client"
import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"
import {
  logBroadcast,
  logBroadcastVideoElementHealth,
} from "./tradeRoomBroadcastDiagnostics.ts"

const attachedByTrackSid = new Map<string, HTMLVideoElement>()

export function attachBroadcastVideoTrack(
  track: RemoteTrack,
  videoEl: HTMLVideoElement
): void {
  if (track.kind !== Track.Kind.Video) return
  const sid = track.sid ?? track.mediaStreamTrack.id
  track.attach(videoEl)
  videoEl.muted = true
  videoEl.playsInline = true
  videoEl.autoplay = true
  attachedByTrackSid.set(sid, videoEl)
  logBroadcast("remote viewer video attached", {
    trackSid: sid,
    trackSource: String(pubSourceFromTrack(track)),
  })
  void videoEl.play().then(
    () => logBroadcastVideoElementHealth("remote viewer after play()", videoEl),
    (err) =>
      logBroadcast("remote viewer play() rejected", {
        message: err instanceof Error ? err.message : String(err),
      })
  )
}

function pubSourceFromTrack(track: RemoteTrack): string {
  return String(track.source ?? "unknown")
}

export function detachBroadcastVideoTrack(track: RemoteTrack): void {
  const sid = track.sid ?? track.mediaStreamTrack.id
  const el = attachedByTrackSid.get(sid)
  if (el) {
    track.detach(el)
    attachedByTrackSid.delete(sid)
  } else {
    track.detach()
  }
}

export function cleanupBroadcastVideoAttachments(): void {
  attachedByTrackSid.clear()
}

export function isBroadcastScreenSharePublication(
  pub: RemoteTrackPublication
): boolean {
  const source = pub.source as Track.Source | string
  return (
    source === Track.Source.ScreenShare ||
    source === Track.Source.ScreenShareAudio ||
    source === "screen_share" ||
    source === "screen_share_video"
  )
}

export function isBroadcastCameraPublication(
  pub: RemoteTrackPublication
): boolean {
  return pub.source === Track.Source.Camera
}

export function isBroadcastVideoPublication(
  pub: RemoteTrackPublication
): boolean {
  return isBroadcastScreenSharePublication(pub) || isBroadcastCameraPublication(pub)
}

export function findBroadcasterVideoPublication(
  room: Room,
  broadcasterIdentity: string,
  preferredSource: TradeRoomBroadcastVideoSource
): RemoteTrackPublication | null {
  const participant = room.remoteParticipants.get(broadcasterIdentity) as
    | RemoteParticipant
    | undefined
  if (!participant) return null

  const pubs: RemoteTrackPublication[] = []
  for (const pub of participant.videoTrackPublications.values()) {
    if (!isBroadcastVideoPublication(pub)) continue
    if (pub.track) {
      pubs.push(pub)
    } else if (pub.isSubscribed && pub.videoTrack) {
      pubs.push(pub)
    }
  }

  const preferScreen = preferredSource === "screen"
  const primary = pubs.find((p) =>
    preferScreen
      ? isBroadcastScreenSharePublication(p)
      : isBroadcastCameraPublication(p)
  )
  if (primary) return primary
  return pubs[0] ?? null
}

export function registerBroadcastVideoHandlers(
  room: Room,
  broadcasterIdentity: string,
  videoEl: HTMLVideoElement,
  preferredSource: TradeRoomBroadcastVideoSource = "screen"
): () => void {
  const tryAttach = () => {
    const pub = findBroadcasterVideoPublication(
      room,
      broadcasterIdentity,
      preferredSource
    )
    const track = pub?.track ?? pub?.videoTrack
    if (track) {
      attachBroadcastVideoTrack(track as RemoteTrack, videoEl)
    }
  }

  const onSubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (participant.identity !== broadcasterIdentity) return
    if (!isBroadcastVideoPublication(pub)) return
    if (track.kind === Track.Kind.Video) {
      attachBroadcastVideoTrack(track, videoEl)
    }
  }

  const onUnsubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (participant.identity !== broadcasterIdentity) return
    if (!isBroadcastVideoPublication(pub)) return
    if (track.kind === Track.Kind.Video) {
      detachBroadcastVideoTrack(track)
    }
  }

  const onParticipantConnected = (participant: RemoteParticipant) => {
    if (participant.identity === broadcasterIdentity) {
      tryAttach()
    }
  }

  room.on(RoomEvent.TrackSubscribed, onSubscribed)
  room.on(RoomEvent.TrackUnsubscribed, onUnsubscribed)
  room.on(RoomEvent.ParticipantConnected, onParticipantConnected)
  tryAttach()

  return () => {
    room.off(RoomEvent.TrackSubscribed, onSubscribed)
    room.off(RoomEvent.TrackUnsubscribed, onUnsubscribed)
    room.off(RoomEvent.ParticipantConnected, onParticipantConnected)
    cleanupBroadcastVideoAttachments()
  }
}

export function countBroadcastAudience(
  room: Room,
  broadcasterIdentity: string
): number {
  let count = 0
  if (room.localParticipant.identity !== broadcasterIdentity) {
    count += 1
  }
  for (const p of room.remoteParticipants.values()) {
    if (p.identity !== broadcasterIdentity) count += 1
  }
  return count
}

/** Re-bind handlers when the React video element remounts. */
export function reattachBroadcastVideoToElement(
  room: Room,
  broadcasterIdentity: string,
  videoEl: HTMLVideoElement,
  preferredSource: TradeRoomBroadcastVideoSource
): void {
  const pub = findBroadcasterVideoPublication(
    room,
    broadcasterIdentity,
    preferredSource
  )
  const track = pub?.track ?? pub?.videoTrack
  if (track) {
    attachBroadcastVideoTrack(track as RemoteTrack, videoEl)
  }
}
