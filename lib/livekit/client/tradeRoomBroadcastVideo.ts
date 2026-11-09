import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type RemoteTrack,
  type RemoteTrackPublication,
} from "livekit-client"
import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"
import { isObsIngressPublisherIdentity } from "../tradeRoomBroadcastObsIdentity.ts"
import {
  logBroadcast,
  logBroadcastVideoElementHealth,
} from "./tradeRoomBroadcastDiagnostics.ts"

const attachedByTrackSid = new Map<string, HTMLVideoElement>()
/** Last RemoteVideoTrack bound per element — needed when OBS ingress publishes multiple videos (camera then program). */
const lastVideoTrackByElement = new WeakMap<HTMLVideoElement, RemoteTrack>()

export function attachBroadcastVideoTrack(
  track: RemoteTrack,
  videoEl: HTMLVideoElement
): void {
  if (track.kind !== Track.Kind.Video) return
  const sid = track.sid ?? track.mediaStreamTrack.id

  const prevTrackOnThisEl = lastVideoTrackByElement.get(videoEl)
  if (prevTrackOnThisEl && prevTrackOnThisEl !== track) {
    try {
      const prevSid = prevTrackOnThisEl.sid ?? prevTrackOnThisEl.mediaStreamTrack.id
      prevTrackOnThisEl.detach(videoEl)
      attachedByTrackSid.delete(prevSid)
    } catch {
      // ignore stale detach
    }
  }

  track.attach(videoEl)
  videoEl.muted = true
  videoEl.playsInline = true
  videoEl.autoplay = true
  attachedByTrackSid.set(sid, videoEl)
  lastVideoTrackByElement.set(videoEl, track)
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
    if (lastVideoTrackByElement.get(el) === track) {
      lastVideoTrackByElement.delete(el)
    }
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

export function resolveBroadcastVideoPublisherIdentity(options: {
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
  broadcasterUserId: string
}): string {
  const primary = options.primaryMediaPublisherIdentity?.trim() || ""
  if (options.broadcastSource === "obs" && primary && isObsIngressPublisherIdentity(primary)) {
    return primary
  }
  return options.broadcasterUserId
}

/** Ingress/OBS program feed: any video publication from the dedicated participant. */
export function findObsProgramVideoPublication(
  room: Room,
  programPublisherIdentity: string
): RemoteTrackPublication | null {
  const participant = room.remoteParticipants.get(programPublisherIdentity) as
    | RemoteParticipant
    | undefined
  if (!participant) return null

  const pubs: RemoteTrackPublication[] = []
  for (const pub of participant.videoTrackPublications.values()) {
    if (pub.kind !== Track.Kind.Video) continue
    if (pub.track || pub.videoTrack) {
      pubs.push(pub)
    }
  }

  /** Prefer screen (typical OBS/ingress labeling), then any non-camera, then camera. */
  const screen = pubs.find((p) => isBroadcastScreenSharePublication(p))
  if (screen) return screen
  const nonCamera = pubs.find((p) => !isBroadcastCameraPublication(p))
  if (nonCamera) return nonCamera
  const camera = pubs.find((p) => isBroadcastCameraPublication(p))
  if (camera) return camera
  return pubs[0] ?? null
}

/** True if `pub` is the publication `findObsProgramVideoPublication` would choose (ingress may publish camera + program). */
export function obsPrimaryPublicationMatches(
  room: Room,
  programPublisherIdentity: string,
  pub: RemoteTrackPublication
): boolean {
  const primary = findObsProgramVideoPublication(room, programPublisherIdentity)
  if (!primary) return false
  if (primary === pub) return true
  const a = primary.track ?? primary.videoTrack
  const b = pub.track ?? pub.videoTrack
  if (a && b) {
    const aid = a.sid ?? a.mediaStreamTrack?.id
    const bid = b.sid ?? b.mediaStreamTrack?.id
    if (aid != null && bid != null) {
      return aid === bid
    }
  }
  return false
}

/**
 * Remove every ingress participant video track from a detached &lt;video&gt; (e.g. panel preview
 * after the host moves preview to global studio). Prevents a stale camera track from staying
 * visible on the old element while the new one shows the program feed.
 */
export function detachObsIngressVideoTracksFromElement(
  room: Room,
  programPublisherIdentity: string,
  videoEl: HTMLVideoElement
): void {
  const participant = room.remoteParticipants.get(programPublisherIdentity) as
    | RemoteParticipant
    | undefined
  if (!participant) return

  for (const pub of participant.videoTrackPublications.values()) {
    if (pub.kind !== Track.Kind.Video) continue
    const t = pub.track ?? pub.videoTrack
    if (!t || t.kind !== Track.Kind.Video) continue
    try {
      t.detach(videoEl)
    } catch {
      // ignore stale detach
    }
    const sid = t.sid ?? t.mediaStreamTrack.id
    if (attachedByTrackSid.get(sid) === videoEl) {
      attachedByTrackSid.delete(sid)
    }
    if (lastVideoTrackByElement.get(videoEl) === t) {
      lastVideoTrackByElement.delete(videoEl)
    }
  }
}

export function broadcastVideoPublicationsMatch(
  a: RemoteTrackPublication,
  b: RemoteTrackPublication
): boolean {
  if (a === b) return true
  const aSid = a.trackSid ?? a.track?.sid ?? a.videoTrack?.sid
  const bSid = b.trackSid ?? b.track?.sid ?? b.videoTrack?.sid
  if (aSid != null && bSid != null && aSid === bSid) return true
  const aMedia = a.track?.mediaStreamTrack?.id ?? a.videoTrack?.mediaStreamTrack?.id
  const bMedia = b.track?.mediaStreamTrack?.id ?? b.videoTrack?.mediaStreamTrack?.id
  return aMedia != null && bMedia != null && aMedia === bMedia
}

/**
 * Browser host program feed: screen-share (composited program) when published, else camera.
 * Ignores stale API `video_source` so mid-stream webcam ↔ screen switches stay in sync.
 */
export function findBrowserBroadcasterProgramVideoPublication(
  room: Room,
  broadcasterIdentity: string
): RemoteTrackPublication | null {
  const participant = room.remoteParticipants.get(broadcasterIdentity) as
    | RemoteParticipant
    | undefined
  if (!participant) return null

  const pubs: RemoteTrackPublication[] = []
  for (const pub of participant.videoTrackPublications.values()) {
    if (!isBroadcastVideoPublication(pub)) continue
    if (pub.track || (pub.isSubscribed && pub.videoTrack)) {
      pubs.push(pub)
    }
  }

  const screen = pubs.find((p) => isBroadcastScreenSharePublication(p))
  if (screen) return screen
  const camera = pubs.find((p) => isBroadcastCameraPublication(p))
  return camera ?? pubs[0] ?? null
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

export function findPrimaryBroadcastVideoPublication(
  room: Room,
  options: {
    broadcastSource?: "browser" | "obs"
    primaryMediaPublisherIdentity?: string | null
    broadcasterUserId: string
    preferredSource: TradeRoomBroadcastVideoSource
  }
): RemoteTrackPublication | null {
  if (options.broadcastSource === "obs") {
    const programId = options.primaryMediaPublisherIdentity?.trim() || ""
    if (programId && isObsIngressPublisherIdentity(programId)) {
      return findObsProgramVideoPublication(room, programId)
    }
  }
  return findBrowserBroadcasterProgramVideoPublication(
    room,
    options.broadcasterUserId
  )
}

export function registerBroadcastVideoHandlers(
  room: Room,
  options: {
    broadcastSource?: "browser" | "obs"
    primaryMediaPublisherIdentity?: string | null
    broadcasterUserId: string
    /** Legacy: single identity (browser) — prefer broadcasterUserId + broadcastSource. */
    broadcasterIdentity?: string
    preferredSource: TradeRoomBroadcastVideoSource
    /** Prefer getter so handlers work before the &lt;video&gt; mounts (OBS preview). */
    getVideoElement?: () => HTMLVideoElement | null
    videoEl?: HTMLVideoElement
  }
): () => void {
  const getEl = () => options.getVideoElement?.() ?? options.videoEl ?? null
  const broadcastSource = options.broadcastSource ?? "browser"
  const preferredSource = options.preferredSource
  const broadcasterUserId = options.broadcasterUserId
  const programId =
    options.primaryMediaPublisherIdentity?.trim() ||
    (broadcastSource === "obs" ? "" : "")
  const legacyId = options.broadcasterIdentity ?? broadcasterUserId

  const resolvePublisherId = (): string => {
    if (broadcastSource === "obs" && programId && isObsIngressPublisherIdentity(programId)) {
      return programId
    }
    return legacyId
  }

  const isOurProgramPublisher = (
    participant: RemoteParticipant,
    pub: RemoteTrackPublication
  ) => {
    const id = resolvePublisherId()
    if (participant.identity !== id) return false
    if (broadcastSource === "obs") {
      return pub.kind === Track.Kind.Video
    }
    return isBroadcastVideoPublication(pub)
  }

  const shouldAttachProgramVideoPublication = (
    participant: RemoteParticipant,
    pub: RemoteTrackPublication
  ) => {
    if (!isOurProgramPublisher(participant, pub)) return false
    if (broadcastSource === "obs") {
      const pid = resolvePublisherId()
      return obsPrimaryPublicationMatches(room, pid, pub)
    }
    const program = findBrowserBroadcasterProgramVideoPublication(
      room,
      broadcasterUserId
    )
    if (!program) return false
    return broadcastVideoPublicationsMatch(program, pub)
  }

  const tryAttach = () => {
    const el = getEl()
    if (!el) return
    const pub = findPrimaryBroadcastVideoPublication(room, {
      broadcastSource,
      primaryMediaPublisherIdentity: programId || null,
      broadcasterUserId,
      preferredSource,
    })
    const track = pub?.track ?? pub?.videoTrack
    if (track) {
      attachBroadcastVideoTrack(track as RemoteTrack, el)
    }
  }

  const onSubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (!shouldAttachProgramVideoPublication(participant, pub)) return
    const el = getEl()
    if (!el) return
    if (track.kind === Track.Kind.Video) {
      attachBroadcastVideoTrack(track, el)
    }
  }

  const onUnsubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (!shouldAttachProgramVideoPublication(participant, pub)) return
    if (track.kind === Track.Kind.Video) {
      detachBroadcastVideoTrack(track)
    }
  }

  const onParticipantConnected = (participant: RemoteParticipant) => {
    if (participant.identity === resolvePublisherId()) {
      tryAttach()
    }
  }

  const onTrackPublished = (
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (pub.kind !== Track.Kind.Video) return
    if (shouldAttachProgramVideoPublication(participant, pub)) {
      const t = pub.track ?? pub.videoTrack
      const el = getEl()
      if (el && t) attachBroadcastVideoTrack(t as RemoteTrack, el)
      return
    }
    tryAttach()
  }

  const onTrackUnpublished = (
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (!isOurProgramPublisher(participant, pub)) return
    const t = pub.track ?? pub.videoTrack
    if (t) detachBroadcastVideoTrack(t as RemoteTrack)
    if (pub.kind === Track.Kind.Video) {
      tryAttach()
    }
  }

  room.on(RoomEvent.TrackSubscribed, onSubscribed)
  room.on(RoomEvent.TrackUnsubscribed, onUnsubscribed)
  room.on(RoomEvent.ParticipantConnected, onParticipantConnected)
  room.on(RoomEvent.TrackPublished, onTrackPublished)
  room.on(RoomEvent.TrackUnpublished, onTrackUnpublished)
  tryAttach()

  return () => {
    room.off(RoomEvent.TrackSubscribed, onSubscribed)
    room.off(RoomEvent.TrackUnsubscribed, onUnsubscribed)
    room.off(RoomEvent.ParticipantConnected, onParticipantConnected)
    room.off(RoomEvent.TrackPublished, onTrackPublished)
    room.off(RoomEvent.TrackUnpublished, onTrackUnpublished)
    cleanupBroadcastVideoAttachments()
  }
}

export function countBroadcastAudience(
  room: Room,
  broadcasterIdentity: string,
  programPublisherIdentity?: string | null
): number {
  const programId = programPublisherIdentity?.trim() || ""
  let count = 0
  if (room.localParticipant.identity !== broadcasterIdentity) {
    count += 1
  }
  for (const p of room.remoteParticipants.values()) {
    if (p.identity === broadcasterIdentity) continue
    if (programId && p.identity === programId) continue
    count += 1
  }
  return count
}

/** Re-bind handlers when the React video element remounts. */
export function reattachBroadcastVideoToElement(
  room: Room,
  options: {
    broadcastSource?: "browser" | "obs"
    primaryMediaPublisherIdentity?: string | null
    broadcasterUserId: string
    broadcasterIdentity?: string
    videoEl: HTMLVideoElement
    preferredSource: TradeRoomBroadcastVideoSource
  }
): void {
  const pub = findPrimaryBroadcastVideoPublication(room, {
    broadcastSource: options.broadcastSource,
    primaryMediaPublisherIdentity: options.primaryMediaPublisherIdentity,
    broadcasterUserId: options.broadcasterUserId,
    preferredSource: options.preferredSource,
  })
  const track = pub?.track ?? pub?.videoTrack
  if (track) {
    attachBroadcastVideoTrack(track as RemoteTrack, options.videoEl)
  }
}
