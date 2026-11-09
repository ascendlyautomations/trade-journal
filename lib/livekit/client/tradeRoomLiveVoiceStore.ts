"use client"

import {
  ConnectionState,
  Room,
  RoomEvent,
  Track,
  type Participant,
  type RemoteParticipant,
} from "livekit-client"
import { applyLiveVoiceAudioPolicyOnConnect } from "./applyLiveVoiceAudioPolicy.ts"
import { createExternalStoreSnapshotCache } from "./externalStoreSnapshot.ts"
import {
  isLiveVoiceMicrophoneAccessError,
  LIVE_VOICE_LISTEN_ONLY_SUFFIX,
  liveVoiceMicrophoneErrorMessage,
} from "./liveVoiceMicrophoneErrors.ts"
import { TRADE_ROOM_GENERAL_VOICE_LABEL } from "@/lib/livekit/tradeRoomSharedLiveVoice.ts"
import {
  attachExistingRemoteAudio,
  cleanupLiveVoiceRemoteAudio,
  ensureLiveVoicePlayback,
  getLiveVoiceRemoteAudioDiagnostics,
  registerLiveVoiceRemoteAudioHandlers,
  type LiveVoiceRemoteAudioDiagnostics,
} from "./tradeRoomLiveVoiceRemoteAudio.ts"
import { invalidateGeneralVoicePresenceCache } from "./generalVoicePresenceCache.ts"

export type LiveVoiceSessionMeta = {
  roomId: string
  roomLabel: string
  channelLabel: string
  canPublish: boolean
}

export type LiveVoiceParticipantView = {
  identity: string
  name: string
  isLocal: boolean
  isSpeaking: boolean
  isMuted: boolean
}

export type LiveVoiceStoreSnapshot = {
  session: LiveVoiceSessionMeta | null
  connectionState: ConnectionState
  isMicrophoneEnabled: boolean
  participants: LiveVoiceParticipantView[]
  error: string | null
  isBusy: boolean
}

/** Subscription channel without participant list — avoids re-rendering trade room chat on ActiveSpeakersChanged. */
export type LiveVoiceStableSnapshot = {
  session: LiveVoiceSessionMeta | null
  connectionState: ConnectionState
  isMicrophoneEnabled: boolean
  error: string | null
  isBusy: boolean
  /** Connect/disconnect count only; does not change when speaking toggles. */
  participantCount: number
}

export type LiveVoiceParticipantSnapshot = {
  participants: LiveVoiceParticipantView[]
}

type Listener = () => void

const stableListeners = new Set<Listener>()
const participantListeners = new Set<Listener>()
/** @deprecated Full-store subscribers (prefer stable + participant hooks). */
const listeners = new Set<Listener>()

let room: Room | null = null
let session: LiveVoiceSessionMeta | null = null
let connectionState: ConnectionState = ConnectionState.Disconnected
let isMicrophoneEnabled = false
let participants: LiveVoiceParticipantView[] = []
let participantCount = 0
let error: string | null = null
let isBusy = false
let devDiagnostics: LiveVoiceRemoteAudioDiagnostics | null = null

function refreshDevDiagnostics(activeRoom: Room | null) {
  if (process.env.NODE_ENV === "production") {
    devDiagnostics = null
    return
  }
  devDiagnostics = getLiveVoiceRemoteAudioDiagnostics(
    activeRoom,
    isMicrophoneEnabled
  )
}

function buildStoreSnapshot(): LiveVoiceStoreSnapshot {
  return {
    session,
    connectionState,
    isMicrophoneEnabled,
    participants,
    error,
    isBusy,
  }
}

function buildStableSnapshot(): LiveVoiceStableSnapshot {
  return {
    session,
    connectionState,
    isMicrophoneEnabled,
    error,
    isBusy,
    participantCount,
  }
}

function buildParticipantSnapshot(): LiveVoiceParticipantSnapshot {
  return { participants }
}

const snapshotCache = createExternalStoreSnapshotCache(buildStoreSnapshot)
const stableSnapshotCache = createExternalStoreSnapshotCache(buildStableSnapshot)
const participantSnapshotCache = createExternalStoreSnapshotCache(
  buildParticipantSnapshot
)

function publishFullSnapshot() {
  snapshotCache.publish(buildStoreSnapshot)
  for (const listener of listeners) {
    listener()
  }
}

function emitStableOnly() {
  stableSnapshotCache.publish(buildStableSnapshot)
  for (const listener of stableListeners) {
    listener()
  }
  publishFullSnapshot()
}

function emitParticipantsOnly() {
  participantSnapshotCache.publish(buildParticipantSnapshot)
  for (const listener of participantListeners) {
    listener()
  }
  publishFullSnapshot()
}

/** Connection + participant list + counts (join/leave/connect/disconnect/mute errors). */
function emitAllChannels() {
  stableSnapshotCache.publish(buildStableSnapshot)
  for (const listener of stableListeners) {
    listener()
  }
  participantSnapshotCache.publish(buildParticipantSnapshot)
  for (const listener of participantListeners) {
    listener()
  }
  publishFullSnapshot()
}

function participantView(local: Participant, isLocal: boolean): LiveVoiceParticipantView {
  const micPub = local.getTrackPublication(Track.Source.Microphone)
  const muted = micPub?.isMuted !== false && !local.isMicrophoneEnabled
  return {
    identity: local.identity,
    name: local.name || local.identity.slice(0, 8),
    isLocal,
    isSpeaking: local.isSpeaking,
    isMuted: muted,
  }
}

function refreshParticipants(activeRoom: Room) {
  const list: LiveVoiceParticipantView[] = []
  list.push(participantView(activeRoom.localParticipant, true))
  for (const p of activeRoom.remoteParticipants.values()) {
    list.push(participantView(p as RemoteParticipant, false))
  }
  participants = list
  participantCount = list.length
}

function attachRoomHandlers(activeRoom: Room) {
  const syncStableAndParticipants = () => {
    connectionState = activeRoom.state
    refreshParticipants(activeRoom)
    refreshDevDiagnostics(activeRoom)
    emitAllChannels()
  }

  const syncParticipantsOnly = () => {
    refreshParticipants(activeRoom)
    emitParticipantsOnly()
  }

  activeRoom
    .on(RoomEvent.ConnectionStateChanged, syncStableAndParticipants)
    .on(RoomEvent.ParticipantConnected, syncStableAndParticipants)
    .on(RoomEvent.ParticipantDisconnected, syncStableAndParticipants)
    .on(RoomEvent.ActiveSpeakersChanged, syncParticipantsOnly)
    .on(RoomEvent.TrackMuted, syncParticipantsOnly)
    .on(RoomEvent.TrackUnmuted, syncParticipantsOnly)
    .on(RoomEvent.LocalTrackPublished, syncParticipantsOnly)
    .on(RoomEvent.LocalTrackUnpublished, syncParticipantsOnly)

  registerLiveVoiceRemoteAudioHandlers(activeRoom, syncStableAndParticipants)
}

function detachRoomHandlers(activeRoom: Room) {
  activeRoom.removeAllListeners()
  cleanupLiveVoiceRemoteAudio()
}

export function subscribeTradeRoomLiveVoice(listener: Listener): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function subscribeTradeRoomLiveVoiceStable(listener: Listener): () => void {
  stableListeners.add(listener)
  return () => stableListeners.delete(listener)
}

export function subscribeTradeRoomLiveVoiceParticipants(
  listener: Listener
): () => void {
  participantListeners.add(listener)
  return () => participantListeners.delete(listener)
}

export function getTradeRoomLiveVoiceSnapshot(): LiveVoiceStoreSnapshot {
  return snapshotCache.getSnapshot()
}

export function getTradeRoomLiveVoiceStableSnapshot(): LiveVoiceStableSnapshot {
  return stableSnapshotCache.getSnapshot()
}

export function getTradeRoomLiveVoiceParticipantsSnapshot(): LiveVoiceParticipantSnapshot {
  return participantSnapshotCache.getSnapshot()
}

/** Development-only LiveKit audio pipeline stats (null in production). */
export function getTradeRoomLiveVoiceDiagnostics(): LiveVoiceRemoteAudioDiagnostics | null {
  return devDiagnostics
}

export async function leaveTradeRoomLiveVoice(options?: {
  retainError?: boolean
}): Promise<void> {
  isBusy = true
  emitStableOnly()
  const keepError = options?.retainError === true
  const roomIdForPresence = session?.roomId
  try {
    if (room) {
      detachRoomHandlers(room)
      await room.disconnect()
    }
  } catch (err) {
    console.warn("[live-voice] disconnect", err)
  } finally {
    if (roomIdForPresence) {
      invalidateGeneralVoicePresenceCache(roomIdForPresence)
    }
    room = null
    session = null
    connectionState = ConnectionState.Disconnected
    isMicrophoneEnabled = false
    participants = []
    participantCount = 0
    devDiagnostics = null
    if (!keepError) {
      error = null
    }
    isBusy = false
    emitAllChannels()
  }
}

async function enablePublisherMicrophone(activeRoom: Room): Promise<void> {
  await activeRoom.localParticipant.setMicrophoneEnabled(true)
  isMicrophoneEnabled = true
}

function downgradeToListenOnly(activeRoom: Room, micErr: unknown): void {
  isMicrophoneEnabled = false
  if (session) {
    session = { ...session, canPublish: false }
  }
  error =
    liveVoiceMicrophoneErrorMessage(micErr) + LIVE_VOICE_LISTEN_ONLY_SUFFIX
  try {
    void activeRoom.localParticipant.setMicrophoneEnabled(false)
  } catch {
    /* already unavailable */
  }
  refreshParticipants(activeRoom)
}

export async function joinTradeRoomLiveVoice(options: {
  roomId: string
  roomLabel: string
  channelLabel?: string
  fetchToken: () => Promise<{
    token: string
    livekitUrl: string
    canPublish: boolean
  }>
}): Promise<void> {
  if (isBusy) {
    return
  }

  if (
    session &&
    session.roomId === options.roomId &&
    room?.state === ConnectionState.Connected
  ) {
    return
  }

  if (room) {
    await leaveTradeRoomLiveVoice()
  }

  isBusy = true
  error = null
  emitStableOnly()

  let joinedRoom: Room | null = null

  try {
    const { token, livekitUrl, canPublish } = await options.fetchToken()
    applyLiveVoiceAudioPolicyOnConnect()

    const nextRoom = new Room({
      adaptiveStream: true,
      dynacast: true,
      webAudioMix: true,
    })
    attachRoomHandlers(nextRoom)
    room = nextRoom
    joinedRoom = nextRoom
    session = {
      roomId: options.roomId,
      roomLabel: options.roomLabel,
      channelLabel: options.channelLabel?.trim() || TRADE_ROOM_GENERAL_VOICE_LABEL,
      canPublish,
    }

    await nextRoom.connect(livekitUrl, token)
    connectionState = nextRoom.state

    if (canPublish) {
      try {
        await enablePublisherMicrophone(nextRoom)
      } catch (micErr) {
        if (isLiveVoiceMicrophoneAccessError(micErr)) {
          downgradeToListenOnly(nextRoom, micErr)
        } else {
          throw micErr
        }
      }
    } else {
      isMicrophoneEnabled = false
    }

    try {
      await ensureLiveVoicePlayback(nextRoom)
    } catch {
      /* join click counts as user gesture; playback may still unlock on track subscribe */
    }
    attachExistingRemoteAudio(nextRoom)
    refreshParticipants(nextRoom)
    refreshDevDiagnostics(nextRoom)
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not join live voice."
    error = message
    if (joinedRoom) {
      detachRoomHandlers(joinedRoom)
      try {
        await joinedRoom.disconnect()
      } catch (disconnectErr) {
        console.warn("[live-voice] failed join cleanup", disconnectErr)
      }
    }
    room = null
    session = null
    invalidateGeneralVoicePresenceCache(options.roomId)
    connectionState = ConnectionState.Disconnected
    isMicrophoneEnabled = false
    participants = []
    participantCount = 0
    devDiagnostics = null
  } finally {
    isBusy = false
    refreshDevDiagnostics(room)
    emitAllChannels()
  }
}

/** User gesture — unlock browser audio playback when autoplay is blocked. */
export async function resumeTradeRoomLiveVoicePlayback(): Promise<void> {
  if (!room) return
  try {
    await ensureLiveVoicePlayback(room)
    attachExistingRemoteAudio(room)
    error = null
  } catch (err) {
    error =
      err instanceof Error ? err.message : "Could not enable audio playback."
  }
  refreshDevDiagnostics(room)
  emitStableOnly()
}

export async function setTradeRoomLiveVoiceMuted(muted: boolean): Promise<void> {
  if (!room || !session?.canPublish) return
  try {
    await room.localParticipant.setMicrophoneEnabled(!muted)
    isMicrophoneEnabled = !muted
    error = null
    refreshParticipants(room)
    emitAllChannels()
  } catch (err) {
    if (isLiveVoiceMicrophoneAccessError(err)) {
      isMicrophoneEnabled = false
      if (session) {
        session = { ...session, canPublish: false }
      }
      error =
        liveVoiceMicrophoneErrorMessage(err) + LIVE_VOICE_LISTEN_ONLY_SUFFIX
      refreshParticipants(room)
      emitAllChannels()
      return
    }
    console.error("[live-voice] mute", err)
    error = err instanceof Error ? err.message : "Could not change microphone."
    emitStableOnly()
  }
}
