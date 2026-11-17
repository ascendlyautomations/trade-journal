import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type RemoteTrack,
  type RemoteTrackPublication,
} from "livekit-client"
import {
  BROADCAST_MEDIA_ATTR,
  BROADCAST_REMOTE_AUDIO_ROOT_ID,
} from "../mobileWebLivePolicy.ts"
import {
  broadcastElementListen,
  clampBroadcastListenVolume,
  replaceAttachedAudioSlot,
} from "../broadcastListenState.ts"

const ROOT_ID = BROADCAST_REMOTE_AUDIO_ROOT_ID
const attachedBySid = new Map<string, HTMLAudioElement>()
let streamListenMuted = false
let streamListenVolume = 1

function applyListenState(el: HTMLAudioElement): void {
  const next = broadcastElementListen({
    muted: streamListenMuted,
    volume: streamListenVolume,
  })
  el.volume = next.volume
  el.muted = next.muted
}

function applyListenStateAll(): void {
  for (const el of attachedBySid.values()) {
    applyListenState(el)
  }
}

export function setBroadcastStreamListenMuted(muted: boolean): void {
  streamListenMuted = muted
  applyListenStateAll()
}

export function getBroadcastStreamListenMuted(): boolean {
  return streamListenMuted
}

export function setBroadcastStreamListenVolume(volume: number): void {
  streamListenVolume = clampBroadcastListenVolume(volume)
  applyListenStateAll()
}

export function getBroadcastStreamListenVolume(): number {
  return streamListenVolume
}

function audioRoot(): HTMLElement | null {
  if (typeof document === "undefined") return null
  let el = document.getElementById(ROOT_ID)
  if (!el) {
    el = document.createElement("div")
    el.id = ROOT_ID
    el.hidden = true
    el.setAttribute("aria-hidden", "true")
    el.setAttribute(BROADCAST_MEDIA_ATTR, "true")
    document.body.appendChild(el)
  }
  return el
}

function attachRemoteAudio(track: RemoteTrack): void {
  if (track.kind !== Track.Kind.Audio) return
  const sid = track.sid ?? track.mediaStreamTrack.id
  const root = audioRoot()
  if (!root) return
  const el = track.attach() as HTMLAudioElement
  el.autoplay = true
  applyListenState(el)
  replaceAttachedAudioSlot(attachedBySid, sid, el, (previous) => {
    try {
      track.detach(previous)
    } catch {
      /* stale element */
    }
    previous.remove()
  })
  root.appendChild(el)
  void el.play().catch(() => {})
}

/** Replay already-attached program audio without changing mute or volume. */
export function replayBroadcastRemoteAudio(): void {
  for (const el of attachedBySid.values()) {
    applyListenState(el)
    if (streamListenMuted) continue
    void el.play().catch(() => {})
  }
}

function detachRemoteAudio(track: RemoteTrack): void {
  const sid = track.sid ?? track.mediaStreamTrack.id
  const el = attachedBySid.get(sid)
  if (el) {
    track.detach(el)
    el.remove()
    attachedBySid.delete(sid)
  } else {
    track.detach()
  }
}

export function cleanupBroadcastRemoteAudio(options?: {
  preserveListenMute?: boolean
}): void {
  attachedBySid.clear()
  document.getElementById(ROOT_ID)?.replaceChildren()
  if (!options?.preserveListenMute) {
    streamListenMuted = false
    streamListenVolume = 1
  }
}

export type BroadcastRemoteAudioContext = {
  broadcasterUserId: string
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
}

export function shouldAttachRemoteBroadcastAudio(
  ctx: BroadcastRemoteAudioContext,
  participant: RemoteParticipant,
  pub: RemoteTrackPublication
): boolean {
  if (pub.kind !== Track.Kind.Audio) return false
  const hostId = ctx.broadcasterUserId
  const programId = ctx.primaryMediaPublisherIdentity?.trim() || ""
  const isObs = ctx.broadcastSource === "obs" && programId !== ""

  // OBS program feed: Ingress may publish audio with non-microphone TrackSource — play all audio tracks once.
  if (isObs && participant.identity === programId) {
    return true
  }

  if (pub.source === Track.Source.Microphone) {
    // Browser host mic, or OBS host moderation mic, or invited / open-voice speakers.
    return true
  }

  // Tab / display audio is a separate track from the microphone. Only the host's copy.
  if (
    pub.source === Track.Source.ScreenShareAudio &&
    hostId !== "" &&
    participant.identity === hostId
  ) {
    return true
  }

  return false
}

export function registerBroadcastRemoteAudioHandlers(
  room: Room,
  ctx: BroadcastRemoteAudioContext
): () => void {
  const shouldAttach = (participant: RemoteParticipant, pub: RemoteTrackPublication) =>
    shouldAttachRemoteBroadcastAudio(ctx, participant, pub)

  const onSubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (track.kind !== Track.Kind.Audio) return
    if (!shouldAttach(participant, pub)) return
    attachRemoteAudio(track)
  }

  const onUnsubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (track.kind !== Track.Kind.Audio) return
    if (!shouldAttach(participant, pub)) return
    detachRemoteAudio(track)
  }

  room.on(RoomEvent.TrackSubscribed, onSubscribed)
  room.on(RoomEvent.TrackUnsubscribed, onUnsubscribed)

  for (const participant of room.remoteParticipants.values()) {
    for (const pub of participant.audioTrackPublications.values()) {
      if (pub.isSubscribed && pub.track && shouldAttach(participant, pub)) {
        attachRemoteAudio(pub.track as RemoteTrack)
      }
    }
  }

  return () => {
    room.off(RoomEvent.TrackSubscribed, onSubscribed)
    room.off(RoomEvent.TrackUnsubscribed, onUnsubscribed)
    cleanupBroadcastRemoteAudio({ preserveListenMute: true })
  }
}
