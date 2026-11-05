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

export type LiveVoiceSessionMeta = {
  roomId: string
  sectionId: string
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

function emit() {
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
  return {
    session,
    connectionState,
    isMicrophoneEnabled,
    participants,
    error,
    isBusy,
  }
}

export async function leaveTradeRoomLiveVoice(): Promise<void> {
  isBusy = true
  emit()
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
    error = null
    isBusy = false
    emit()
  }
}

export async function joinTradeRoomLiveVoice(options: {
  roomId: string
  sectionId: string
  roomLabel: string
  channelLabel: string
  fetchToken: () => Promise<{
    token: string
    livekitUrl: string
    canPublish: boolean
  }>
}): Promise<void> {
  if (
    session &&
    session.roomId === options.roomId &&
    session.sectionId === options.sectionId &&
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

  try {
    const { token, livekitUrl, canPublish } = await options.fetchToken()
    applyLiveVoiceAudioPolicyOnConnect()

    const nextRoom = new Room({
      adaptiveStream: true,
      dynacast: true,
    })
    attachRoomHandlers(nextRoom)
    room = nextRoom
    session = {
      roomId: options.roomId,
      sectionId: options.sectionId,
      roomLabel: options.roomLabel,
      channelLabel: options.channelLabel,
      canPublish,
    }

    await nextRoom.connect(livekitUrl, token)
    connectionState = nextRoom.state

    if (canPublish) {
      await nextRoom.localParticipant.setMicrophoneEnabled(true)
      isMicrophoneEnabled = true
    } else {
      isMicrophoneEnabled = false
    }

    refreshParticipants(nextRoom)
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not join live voice."
    await leaveTradeRoomLiveVoice()
    throw err
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
    refreshParticipants(room)
    emit()
  } catch (err) {
    console.error("[live-voice] mute", err)
  }
}
