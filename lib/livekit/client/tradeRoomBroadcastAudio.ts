import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type RemoteTrack,
  type RemoteTrackPublication,
} from "livekit-client"

const ROOT_ID = "tradetraxs-broadcast-remote-audio"
const attachedBySid = new Map<string, HTMLAudioElement>()
let streamListenMuted = false

export function setBroadcastStreamListenMuted(muted: boolean): void {
  streamListenMuted = muted
  for (const el of attachedBySid.values()) {
    el.muted = muted
  }
}

export function getBroadcastStreamListenMuted(): boolean {
  return streamListenMuted
}

function audioRoot(): HTMLElement | null {
  if (typeof document === "undefined") return null
  let el = document.getElementById(ROOT_ID)
  if (!el) {
    el = document.createElement("div")
    el.id = ROOT_ID
    el.hidden = true
    el.setAttribute("aria-hidden", "true")
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
  el.muted = streamListenMuted
  attachedBySid.set(sid, el)
  root.appendChild(el)
  void el.play().catch(() => {})
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

export function cleanupBroadcastRemoteAudio(): void {
  attachedBySid.clear()
  document.getElementById(ROOT_ID)?.replaceChildren()
  streamListenMuted = false
}

function isMicPublication(pub: RemoteTrackPublication): boolean {
  return pub.source === Track.Source.Microphone
}

export function registerBroadcastRemoteAudioHandlers(
  room: Room,
  broadcasterIdentity: string,
  includeConversationParticipants: boolean
): () => void {
  const shouldAttach = (participant: RemoteParticipant, pub: RemoteTrackPublication) => {
    if (pub.source === Track.Source.Microphone) {
      if (participant.identity === broadcasterIdentity) return true
      return includeConversationParticipants
    }
    return false
  }

  const onSubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (track.kind !== Track.Kind.Audio) return
    if (!isMicPublication(pub)) return
    if (!shouldAttach(participant, pub)) return
    attachRemoteAudio(track)
  }

  const onUnsubscribed = (
    track: RemoteTrack,
    pub: RemoteTrackPublication,
    participant: RemoteParticipant
  ) => {
    if (track.kind !== Track.Kind.Audio) return
    if (!isMicPublication(pub)) return
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
    cleanupBroadcastRemoteAudio()
  }
}
