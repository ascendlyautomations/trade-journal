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

type Listener = () => void

const listeners = new Set<Listener>()

let room: Room | null = null
let session: LiveVoiceSessionMeta | null = null
let connectionState: ConnectionState = ConnectionState.Disconnected
let isMicrophoneEnabled = false
let participants: LiveVoiceParticipantView[] = []
let error: string | null = null
let isBusy = false

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

const snapshotCache = createExternalStoreSnapshotCache(buildStoreSnapshot)

function emit() {
  snapshotCache.publish(buildStoreSnapshot)
  for (const listener of listeners) {
    listener()
  }
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
}

function attachRoomHandlers(activeRoom: Room) {
  const sync = () => {
    connectionState = activeRoom.state
    refreshParticipants(activeRoom)
    emit()
  }
  activeRoom
    .on(RoomEvent.ConnectionStateChanged, sync)
    .on(RoomEvent.ParticipantConnected, sync)
    .on(RoomEvent.ParticipantDisconnected, sync)
    .on(RoomEvent.ActiveSpeakersChanged, sync)
    .on(RoomEvent.TrackMuted, sync)
    .on(RoomEvent.TrackUnmuted, sync)
    .on(RoomEvent.LocalTrackPublished, sync)
    .on(RoomEvent.LocalTrackUnpublished, sync)
}

function detachRoomHandlers(activeRoom: Room) {
  activeRoom.removeAllListeners()
}

export function subscribeTradeRoomLiveVoice(listener: Listener): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getTradeRoomLiveVoiceSnapshot(): LiveVoiceStoreSnapshot {
  return snapshotCache.getSnapshot()
}

export async function leaveTradeRoomLiveVoice(options?: {
  retainError?: boolean
}): Promise<void> {
  isBusy = true
  emit()
  const keepError = options?.retainError === true
  try {
    if (room) {
      detachRoomHandlers(room)
      await room.disconnect()
    }
  } catch (err) {
    console.warn("[live-voice] disconnect", err)
  } finally {
    room = null
    session = null
    connectionState = ConnectionState.Disconnected
    isMicrophoneEnabled = false
    participants = []
    if (!keepError) {
      error = null
    }
    isBusy = false
    emit()
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
  emit()

  let joinedRoom: Room | null = null

  try {
    const { token, livekitUrl, canPublish } = await options.fetchToken()
    applyLiveVoiceAudioPolicyOnConnect()

    const nextRoom = new Room({
      adaptiveStream: true,
      dynacast: true,
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

    refreshParticipants(nextRoom)
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
    connectionState = ConnectionState.Disconnected
    isMicrophoneEnabled = false
    participants = []
  } finally {
    isBusy = false
    emit()
  }
}

export async function setTradeRoomLiveVoiceMuted(muted: boolean): Promise<void> {
  if (!room || !session?.canPublish) return
  try {
    await room.localParticipant.setMicrophoneEnabled(!muted)
    isMicrophoneEnabled = !muted
    error = null
    refreshParticipants(room)
    emit()
  } catch (err) {
    if (isLiveVoiceMicrophoneAccessError(err)) {
      isMicrophoneEnabled = false
      if (session) {
        session = { ...session, canPublish: false }
      }
      error =
        liveVoiceMicrophoneErrorMessage(err) + LIVE_VOICE_LISTEN_ONLY_SUFFIX
      refreshParticipants(room)
      emit()
      return
    }
    console.error("[live-voice] mute", err)
    error = err instanceof Error ? err.message : "Could not change microphone."
    emit()
  }
}
