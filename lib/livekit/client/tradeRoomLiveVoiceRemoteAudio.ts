import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type RemoteTrack,
  type RemoteTrackPublication,
} from "livekit-client"

const REMOTE_AUDIO_ROOT_ID = "tradetraxs-live-voice-remote-audio"

/** sid → attached media element (for cleanup). */
const attachedByTrackSid = new Map<string, HTMLMediaElement>()

let lastPlaybackError: string | null = null

export type LiveVoiceRemoteAudioDiagnostics = {
  connectionState: string
  canPlaybackAudio: boolean
  localMicPublished: boolean
  localMicMuted: boolean
  remoteAudioTrackCount: number
  remoteSubscribedAudioCount: number
  attachedRemoteElementCount: number
  playbackError: string | null
}

export function getLiveVoiceRemoteAudioDiagnostics(
  room: Room | null,
  isMicrophoneEnabled: boolean
): LiveVoiceRemoteAudioDiagnostics {
  const localMicPub = room?.localParticipant.getTrackPublication(
    Track.Source.Microphone
  )
  let remoteAudioTrackCount = 0
  let remoteSubscribedAudioCount = 0

  if (room) {
    for (const participant of room.remoteParticipants.values()) {
      for (const pub of participant.audioTrackPublications.values()) {
        remoteAudioTrackCount += 1
        if (pub.isSubscribed && pub.track) {
          remoteSubscribedAudioCount += 1
        }
      }
    }
  }

  return {
    connectionState: room?.state ?? "disconnected",
    canPlaybackAudio: room?.canPlaybackAudio ?? false,
    localMicPublished: Boolean(localMicPub?.track),
    localMicMuted: localMicPub?.isMuted !== false && !isMicrophoneEnabled,
    remoteAudioTrackCount,
    remoteSubscribedAudioCount,
    attachedRemoteElementCount: attachedByTrackSid.size,
    playbackError: lastPlaybackError,
  }
}

function remoteAudioRoot(): HTMLElement | null {
  if (typeof document === "undefined") return null
  let el = document.getElementById(REMOTE_AUDIO_ROOT_ID)
  if (!el) {
    el = document.createElement("div")
    el.id = REMOTE_AUDIO_ROOT_ID
    el.setAttribute("aria-hidden", "true")
    el.hidden = true
    document.body.appendChild(el)
  }
  return el
}

function trackSid(track: RemoteTrack): string {
  return track.sid ?? track.mediaStreamTrack.id
}

export function attachRemoteAudioTrack(track: RemoteTrack): HTMLMediaElement | null {
  if (track.kind !== Track.Kind.Audio) return null
  const sid = trackSid(track)
  if (attachedByTrackSid.has(sid)) {
    return attachedByTrackSid.get(sid) ?? null
  }
  const root = remoteAudioRoot()
  if (!root) return null

  const element = track.attach()
  if (element instanceof HTMLAudioElement) {
    element.autoplay = true
    element.setAttribute("playsinline", "true")
  }
  root.appendChild(element)
  attachedByTrackSid.set(sid, element)
  return element
}

export function detachRemoteAudioTrack(track: RemoteTrack): void {
  const sid = trackSid(track)
  const existing = attachedByTrackSid.get(sid)
  if (existing) {
    track.detach(existing)
    existing.remove()
    attachedByTrackSid.delete(sid)
    return
  }
  const detached = track.detach()
  for (const el of detached) {
    el.remove()
  }
  attachedByTrackSid.delete(sid)
}

export function attachExistingRemoteAudio(room: Room): void {
  for (const participant of room.remoteParticipants.values()) {
    attachParticipantRemoteAudio(participant)
  }
}

function attachParticipantRemoteAudio(participant: RemoteParticipant): void {
  for (const pub of participant.audioTrackPublications.values()) {
    const track = pub.track
    if (track && track.kind === Track.Kind.Audio) {
      attachRemoteAudioTrack(track)
    }
  }
}

export async function ensureLiveVoicePlayback(room: Room): Promise<void> {
  if (room.canPlaybackAudio) return
  try {
    await room.startAudio()
    lastPlaybackError = null
  } catch (err) {
    lastPlaybackError =
      err instanceof Error ? err.message : "Could not start audio playback."
    throw err
  }
}

export function cleanupLiveVoiceRemoteAudio(): void {
  for (const [sid, element] of attachedByTrackSid) {
    element.remove()
    attachedByTrackSid.delete(sid)
  }
  const root = document.getElementById(REMOTE_AUDIO_ROOT_ID)
  root?.remove()
  lastPlaybackError = null
}

export function registerLiveVoiceRemoteAudioHandlers(
  room: Room,
  onChange: () => void
): void {
  const onSubscribe = (
    track: RemoteTrack,
    _pub: RemoteTrackPublication,
    _participant: RemoteParticipant
  ) => {
    if (track.kind === Track.Kind.Audio) {
      attachRemoteAudioTrack(track)
      void ensureLiveVoicePlayback(room).finally(onChange)
      onChange()
    }
  }

  const onUnsubscribe = (track: RemoteTrack) => {
    if (track.kind === Track.Kind.Audio) {
      detachRemoteAudioTrack(track)
      onChange()
    }
  }

  room
    .on(RoomEvent.TrackSubscribed, onSubscribe)
    .on(RoomEvent.TrackUnsubscribed, onUnsubscribe)
    .on(RoomEvent.ParticipantConnected, (participant) => {
      attachParticipantRemoteAudio(participant)
      onChange()
    })
    .on(RoomEvent.ConnectionStateChanged, () => {
      onChange()
    })
}
