"use client"

import {
  ConnectionState,
  Room,
  RoomEvent,
  Track,
} from "livekit-client"
import { createExternalStoreSnapshotCache } from "./externalStoreSnapshot.ts"
import { broadcastStartErrorMessage } from "./tradeRoomBroadcastErrors.ts"
import { setBroadcastPublisherCredentials } from "./tradeRoomBroadcastPublisherLifecycle.ts"
import {
  cleanupBroadcastRemoteAudio,
  getBroadcastStreamListenMuted,
  registerBroadcastRemoteAudioHandlers,
  setBroadcastStreamListenMuted,
} from "./tradeRoomBroadcastAudio.ts"
import {
  clearBroadcastChatState,
  publishBroadcastChatMessage,
  registerBroadcastChatHandlers,
  trimBroadcastChatMessages,
  type BroadcastChatMessage,
} from "./tradeRoomBroadcastChat.ts"
import {
  publishBroadcastHandState,
  registerBroadcastHandHandlers,
  type BroadcastHandState,
} from "./tradeRoomBroadcastHand.ts"
import {
  cleanupBroadcastVideoAttachments,
  countBroadcastAudience,
  reattachBroadcastVideoToElement,
  registerBroadcastVideoHandlers,
} from "./tradeRoomBroadcastVideo.ts"
import { logBroadcast } from "./tradeRoomBroadcastDiagnostics.ts"
import {
  detachLocalBroadcastPreview,
  findLocalBroadcastVideoPublication,
  registerLocalBroadcastPreviewHandlers,
  syncLocalBroadcastPreviewToElement,
} from "./tradeRoomBroadcastLocalPreview.ts"
import { clearBroadcastChatProfileCache } from "./tradeRoomBroadcastChatProfiles.ts"
import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "../tradeRoomBroadcastVoiceMode.ts"
import {
  getTradeRoomLiveVoiceSnapshot,
  leaveTradeRoomLiveVoice,
} from "./tradeRoomLiveVoiceStore.ts"
import { fetchBroadcastConversationJoinPayload } from "./tradeRoomBroadcastJoinConversation.ts"

export type BroadcastRoomStatus = {
  live: boolean
  broadcastSessionId?: string
  broadcasterUserId?: string
  broadcasterDisplayName?: string | null
  startedAt?: string
  viewerCount?: number | null
  voiceMode?: TradeRoomBroadcastVoiceMode
  videoSource?: TradeRoomBroadcastVideoSource
  broadcasterConnected?: boolean | null
  alreadyLiveElsewhere?: boolean
}

export type BroadcastRole = "none" | "broadcaster" | "viewer" | "conversation"

export type BroadcastStudioPresentation = "hidden" | "studio" | "mini"

export type BroadcastStoreSnapshot = {
  roomId: string | null
  roomTitle: string | null
  role: BroadcastRole
  connectionState: ConnectionState
  isBusy: boolean
  error: string | null
  status: BroadcastRoomStatus
  localViewerCount: number
  isWatching: boolean
  isPublishing: boolean
  isInConversation: boolean
  broadcasterMicMuted: boolean
  broadcasterMicWarning: string | null
  chatMessages: BroadcastChatMessage[]
  generalVoiceOverlapWarning: string | null
  broadcasterPreviewError: string | null
  studioPresentation: BroadcastStudioPresentation
  localHandRaised: boolean
  raisedHandIdentities: string[]
  handFeedback: string | null
  liveParticipants: BroadcastLiveParticipant[]
  interactiveProfiles: Record<string, BroadcastInteractiveProfileLite>
  streamListenMuted: boolean
  viewerMicMuted: boolean
  speakInviteNotice: BroadcastSpeakInviteNotice | null
  viewerUserId: string | null
  speakerGrantUserIds: string[]
  sessionBlockUserIds: string[]
  viewerStreamRemovalNotice: BroadcastViewerStreamRemovalNotice | null
  speakerUpgradeInFlight: boolean
}

export type BroadcastViewerStreamRemovalNotice = {
  kind: "removed" | "banned"
  sessionId: string
}

export type BroadcastSpeakInviteNotice = {
  sessionId: string
  roomId: string
  invitationId: string | null
}

export type BroadcastPassiveInteractiveContext = {
  roomId: string
  viewerUserId: string
}

export type BroadcastLiveParticipant = {
  userId: string
  displayName: string
  isBroadcaster: boolean
}

export type BroadcastInteractiveProfileLite = {
  userId: string
  displayName: string
  username: string | null
  avatarUrl: string | null
}

type Listener = () => void

const listeners = new Set<Listener>()

let broadcastRoom: Room | null = null
let roomId: string | null = null
let role: BroadcastRole = "none"
let connectionState: ConnectionState = ConnectionState.Disconnected
let isBusy = false
let error: string | null = null
let status: BroadcastRoomStatus = { live: false }
let localViewerCount = 0
let isWatching = false
let isPublishing = false
let isInConversation = false
let broadcasterMicMuted = false
let broadcasterMicWarning: string | null = null
let chatMessages: BroadcastChatMessage[] = []
let generalVoiceOverlapWarning: string | null = null
let videoCleanup: (() => void) | null = null
let audioCleanup: (() => void) | null = null
let chatCleanup: (() => void) | null = null
let handCleanup: (() => void) | null = null
let localPreviewCleanup: (() => void) | null = null
let studioPresentation: BroadcastStudioPresentation = "hidden"
let roomTitle: string | null = null
let localHandRaised = false
let raisedHandIdentities: string[] = []
let handFeedback: string | null = null
let liveParticipants: BroadcastLiveParticipant[] = []
let interactiveProfiles: Record<string, BroadcastInteractiveProfileLite> = {}
let streamListenMuted = false
let viewerMicMuted = false
let speakInviteNotice: BroadcastSpeakInviteNotice | null = null
let viewerUserId: string | null = null
let viewerAccessToken: string | null = null
let dismissedSpeakInviteSessionId: string | null = null
let speakerUpgradeInFlight = false
let interactivePollTimer: ReturnType<typeof setInterval> | null = null
let speakerGrantUserIds: string[] = []
let sessionBlockUserIds: string[] = []
let boundViewerVideoElement: HTMLVideoElement | null = null
let broadcasterPreviewElement: HTMLVideoElement | null = null
let broadcasterPreviewError: string | null = null
let currentSessionId: string | null = null
let preferredVideoSource: TradeRoomBroadcastVideoSource = "screen"
let broadcasterIdentityForRoom: string | null = null
let viewerStreamRemovalNotice: BroadcastViewerStreamRemovalNotice | null = null
let intentionalBroadcastRoomTeardown = false
let viewerRemovalHandling = false
let passiveInteractiveContext: BroadcastPassiveInteractiveContext | null = null
let speakerAutoUpgradeAttemptedSessionId: string | null = null

function buildSnapshot(): BroadcastStoreSnapshot {
  return {
    roomId,
    role,
    connectionState,
    isBusy,
    error,
    status,
    localViewerCount,
    isWatching,
    isPublishing,
    isInConversation,
    broadcasterMicMuted,
    broadcasterMicWarning,
    chatMessages,
    generalVoiceOverlapWarning,
    broadcasterPreviewError,
    studioPresentation,
    localHandRaised,
    raisedHandIdentities,
    handFeedback,
    roomTitle,
    liveParticipants,
    interactiveProfiles,
    streamListenMuted,
    viewerMicMuted,
    speakInviteNotice,
    viewerUserId,
    speakerGrantUserIds,
    sessionBlockUserIds,
    viewerStreamRemovalNotice,
    speakerUpgradeInFlight,
  }
}

const snapshotCache = createExternalStoreSnapshotCache(buildSnapshot)

function emit() {
  snapshotCache.publish(buildSnapshot)
  for (const listener of listeners) {
    listener()
  }
}

function resetChatForNewSession(sessionId: string | null) {
  if (sessionId === currentSessionId) return
  chatMessages = []
  clearBroadcastChatState()
}

function syncAudienceCount(activeRoom: Room, broadcasterId: string) {
  localViewerCount = countBroadcastAudience(activeRoom, broadcasterId)
}

function syncLiveParticipantRoster(activeRoom: Room, broadcasterId: string) {
  const roster: BroadcastLiveParticipant[] = []
  const seen = new Set<string>()

  const pushParticipant = (
    userId: string,
    fallbackName: string,
    isBroadcaster: boolean
  ) => {
    if (!userId || seen.has(userId)) return
    seen.add(userId)
    roster.push({
      userId,
      displayName:
        interactiveProfiles[userId]?.displayName ||
        fallbackName ||
        "Member",
      isBroadcaster,
    })
  }

  pushParticipant(
    broadcasterId,
    status.broadcasterDisplayName?.trim() ||
      activeRoom.localParticipant.name?.trim() ||
      "Broadcaster",
    true
  )

  for (const participant of activeRoom.remoteParticipants.values()) {
    const userId = participant.identity
    pushParticipant(
      userId,
      participant.name?.trim() || "Member",
      userId === broadcasterId
    )
  }

  liveParticipants = roster
}

function attachRoomSync(activeRoom: Room, broadcasterId: string) {
  const sync = () => {
    connectionState = activeRoom.state
    syncAudienceCount(activeRoom, broadcasterId)
    syncLiveParticipantRoster(activeRoom, broadcasterId)
    emit()
  }
  activeRoom.on(RoomEvent.ConnectionStateChanged, sync)
  activeRoom.on(RoomEvent.ParticipantConnected, sync)
  activeRoom.on(RoomEvent.ParticipantDisconnected, sync)
  activeRoom.on(RoomEvent.Disconnected, () => {
    void handleViewerKickedFromBroadcastRoom()
  })
  sync()
}

async function handleViewerKickedFromBroadcastRoom(): Promise<void> {
  if (
    isPublishing ||
    intentionalBroadcastRoomTeardown ||
    speakerUpgradeInFlight
  ) {
    return
  }
  if (!isWatching && role !== "viewer" && role !== "conversation") return
  if (viewerRemovalHandling) return

  viewerRemovalHandling = true
  try {
    const sessionId = currentSessionId ?? ""
    let kind: BroadcastViewerStreamRemovalNotice["kind"] = "removed"

    if (
      viewerUserId &&
      sessionBlockUserIds.includes(viewerUserId)
    ) {
      kind = "banned"
    } else if (viewerAccessToken && roomId) {
      try {
        const res = await fetch(
          `/api/livekit/broadcast/interactive-state?roomId=${encodeURIComponent(roomId)}`,
          { headers: { Authorization: `Bearer ${viewerAccessToken}` } }
        )
        if (res.ok) {
          const payload = (await res.json()) as {
            snapshot?: { removedFromStream?: boolean }
          }
          if (payload.snapshot?.removedFromStream) {
            kind = "banned"
          }
        }
      } catch {
        // Default to removed when LiveKit dropped the participant.
      }
    }

    await forceViewerOffStream({ kind, sessionId })
  } finally {
    viewerRemovalHandling = false
  }
}

async function forceViewerOffStream(
  notice: BroadcastViewerStreamRemovalNotice
): Promise<void> {
  if (isPublishing) return
  if (
    viewerStreamRemovalNotice?.sessionId === notice.sessionId &&
    viewerStreamRemovalNotice.kind === notice.kind
  ) {
    return
  }

  const prevStatus = { ...status }
  const activeVoiceRoomId = roomId

  viewerStreamRemovalNotice = notice
  speakInviteNotice = null
  emit()

  if (
    activeVoiceRoomId &&
    getTradeRoomLiveVoiceSnapshot().session?.roomId === activeVoiceRoomId
  ) {
    void leaveTradeRoomLiveVoice()
  }

  await teardownBroadcastRoom()

  status = prevStatus.live ? prevStatus : { live: false }
  viewerStreamRemovalNotice = notice
  emit()
}

export function acknowledgeTradeRoomBroadcastViewerRemoval(): void {
  viewerStreamRemovalNotice = null
  emit()
}

function registerChat(activeRoom: Room) {
  chatCleanup?.()
  chatCleanup = registerBroadcastChatHandlers(activeRoom, (message) => {
    chatMessages = trimBroadcastChatMessages([...chatMessages, message])
    emit()
  })
}

function applyRemoteHand(state: BroadcastHandState) {
  const set = new Set(raisedHandIdentities)
  if (state.raised) set.add(state.identity)
  else set.delete(state.identity)
  raisedHandIdentities = [...set]
  emit()
}

function registerHand(activeRoom: Room) {
  handCleanup?.()
  handCleanup = registerBroadcastHandHandlers(activeRoom, applyRemoteHand)
}

async function syncHandAuthoritative(
  accessToken: string,
  sessionId: string,
  raised: boolean
): Promise<void> {
  if (!roomId) return
  try {
    await fetch("/api/livekit/broadcast/hand", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ roomId, sessionId, raised }),
    })
  } catch {
    // LiveKit data + poll reconcile if API fails transiently.
  }
}

export function setBroadcastPassiveInteractiveContext(
  context: BroadcastPassiveInteractiveContext | null
): void {
  passiveInteractiveContext = context
}

export async function refreshBroadcastInteractiveState(
  accessToken: string
): Promise<void> {
  const effectiveRoomId = roomId ?? passiveInteractiveContext?.roomId
  const effectiveViewerUserId =
    viewerUserId ?? passiveInteractiveContext?.viewerUserId
  if (!effectiveRoomId || !accessToken) return
  try {
    const res = await fetch(
      `/api/livekit/broadcast/interactive-state?roomId=${encodeURIComponent(effectiveRoomId)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    )
    if (!res.ok) return
    const payload = (await res.json()) as {
      snapshot?: {
        sessionId?: string
        raisedHands?: Array<{ userId: string }>
        speakerGrants?: string[]
        sessionBlocks?: string[]
        removedFromStream?: boolean
        pendingInvitationForViewer?: { invitationId: string } | null
      }
      profiles?: Array<{
        userId: string
        username: string | null
        displayName: string | null
        avatarUrl: string | null
      }>
    }
    raisedHandIdentities = (payload.snapshot?.raisedHands ?? []).map((h) => h.userId)
    const sessionId = payload.snapshot?.sessionId ?? currentSessionId
    const grants = payload.snapshot?.speakerGrants ?? []
    speakerGrantUserIds = grants
    sessionBlockUserIds = payload.snapshot?.sessionBlocks ?? []
    const pendingInvite = payload.snapshot?.pendingInvitationForViewer
    if (
      payload.snapshot?.removedFromStream &&
      isWatching &&
      !isPublishing
    ) {
      await forceViewerOffStream({
        kind: "banned",
        sessionId: sessionId ?? currentSessionId ?? "",
      })
      return
    }
    const hasSpeakerGrant =
      Boolean(effectiveViewerUserId) &&
      grants.includes(effectiveViewerUserId as string)

    if (
      effectiveViewerUserId &&
      !isPublishing &&
      sessionId &&
      role !== "broadcaster" &&
      role !== "conversation" &&
      !speakerUpgradeInFlight
    ) {
      const invited = hasSpeakerGrant || pendingInvite?.invitationId != null
      if (
        invited &&
        dismissedSpeakInviteSessionId !== sessionId &&
        !speakInviteNotice
      ) {
        speakInviteNotice = {
          sessionId,
          roomId: effectiveRoomId,
          invitationId: pendingInvite?.invitationId ?? null,
        }
      }
    }

    if (
      hasSpeakerGrant &&
      isWatching &&
      role === "viewer" &&
      roomId === effectiveRoomId &&
      boundViewerVideoElement &&
      sessionId
    ) {
      void maybeAutoUpgradeViewerToSpeaker(accessToken, sessionId)
    }
    const nextProfiles: Record<string, BroadcastInteractiveProfileLite> = {
      ...interactiveProfiles,
    }
    for (const profile of payload.profiles ?? []) {
      nextProfiles[profile.userId] = {
        userId: profile.userId,
        username: profile.username,
        displayName:
          profile.displayName?.trim() ||
          profile.username?.trim() ||
          "Member",
        avatarUrl: profile.avatarUrl,
      }
    }
    interactiveProfiles = nextProfiles
    if (broadcastRoom && broadcasterIdentityForRoom) {
      syncLiveParticipantRoster(broadcastRoom, broadcasterIdentityForRoom)
    }
    emit()
  } catch {
    // ignore
  }
}

async function maybeAutoUpgradeViewerToSpeaker(
  accessToken: string,
  sessionId: string
): Promise<void> {
  if (speakerAutoUpgradeAttemptedSessionId === sessionId) return
  if (speakerUpgradeInFlight || isBusy || !roomId || !boundViewerVideoElement) {
    return
  }
  speakerAutoUpgradeAttemptedSessionId = sessionId
  speakerUpgradeInFlight = true
  emit()
  try {
    await joinTradeRoomBroadcastConversation({
      roomId,
      videoElement: boundViewerVideoElement,
      fetchJoin: () => fetchBroadcastConversationJoinPayload(accessToken, roomId),
    })
    speakInviteNotice = null
    viewerMicMuted = false
    error = null
  } catch (err) {
    speakerAutoUpgradeAttemptedSessionId = null
    error =
      err instanceof Error ? err.message : "Could not join as a speaker."
  } finally {
    speakerUpgradeInFlight = false
    emit()
  }
}

function startInteractivePolling(accessToken: string) {
  stopInteractivePolling()
  viewerAccessToken = accessToken
  void refreshBroadcastInteractiveState(accessToken)
  interactivePollTimer = setInterval(() => {
    void refreshBroadcastInteractiveState(accessToken)
  }, 4000)
}

function stopInteractivePolling() {
  if (interactivePollTimer) {
    clearInterval(interactivePollTimer)
    interactivePollTimer = null
  }
}

export function setTradeRoomBroadcastStudioPresentation(
  next: BroadcastStudioPresentation
): void {
  studioPresentation = next
  emit()
}

export function setTradeRoomBroadcastRoomTitle(title: string | null): void {
  roomTitle = title
  emit()
}

export async function toggleTradeRoomBroadcastRaisedHand(options: {
  accessToken: string
  userId: string
}): Promise<void> {
  if (!broadcastRoom || !currentSessionId) return
  if (role !== "viewer" && role !== "conversation") return
  const identity = broadcastRoom.localParticipant.identity
  if (!identity) return
  const next = !localHandRaised
  const published = await publishBroadcastHandState(broadcastRoom, identity, next)
  if (!published.ok) {
    error = published.error
    emit()
    return
  }
  localHandRaised = next
  applyRemoteHand({ identity, raised: next })
  handFeedback = next ? "Hand raised." : "Hand lowered."
  emit()
  await syncHandAuthoritative(options.accessToken, currentSessionId, next)
  window.setTimeout(() => {
    if (handFeedback) {
      handFeedback = null
      emit()
    }
  }, 2200)
}

function registerViewerMedia(
  activeRoom: Room,
  broadcasterId: string,
  videoElement: HTMLVideoElement,
  voiceMode: TradeRoomBroadcastVoiceMode
) {
  videoCleanup?.()
  audioCleanup?.()
  videoCleanup = registerBroadcastVideoHandlers(
    activeRoom,
    broadcasterId,
    videoElement,
    preferredVideoSource
  )
  const includeOtherSpeakers =
    voiceMode === "open_voice" || isInConversation || role === "conversation"
  audioCleanup = registerBroadcastRemoteAudioHandlers(
    activeRoom,
    broadcasterId,
    includeOtherSpeakers
  )
}

function generalVoiceWarningIfNeeded(): string | null {
  const voice = getTradeRoomLiveVoiceSnapshot()
  if (
    voice.session?.roomId === roomId &&
    (voice.connectionState === ConnectionState.Connected ||
      voice.connectionState === ConnectionState.Reconnecting)
  ) {
    return "General Voice is active in this room. Mute or leave General Voice to avoid hearing double audio."
  }
  return null
}

async function releaseLocalTracks(activeRoom: Room) {
  try {
    await activeRoom.localParticipant.setMicrophoneEnabled(false)
  } catch {
    // ignore
  }
  try {
    await activeRoom.localParticipant.setScreenShareEnabled(false)
  } catch {
    // ignore
  }
  try {
    await activeRoom.localParticipant.setCameraEnabled(false)
  } catch {
    // ignore
  }
}

async function teardownBroadcastRoom() {
  intentionalBroadcastRoomTeardown = true
  if (broadcastRoom) {
    await releaseLocalTracks(broadcastRoom)
  }
  videoCleanup?.()
  videoCleanup = null
  audioCleanup?.()
  audioCleanup = null
  chatCleanup?.()
  chatCleanup = null
  handCleanup?.()
  handCleanup = null
  stopInteractivePolling()
  localPreviewCleanup?.()
  localPreviewCleanup = null
  broadcasterPreviewElement = null
  broadcasterPreviewError = null
  cleanupBroadcastVideoAttachments()
  detachLocalBroadcastPreview()
  cleanupBroadcastRemoteAudio()
  if (broadcastRoom) {
    broadcastRoom.removeAllListeners()
    await broadcastRoom.disconnect()
  }
  broadcastRoom = null
  connectionState = ConnectionState.Disconnected
  role = "none"
  isWatching = false
  isPublishing = false
  isInConversation = false
  broadcasterMicMuted = false
  broadcasterMicWarning = null
  generalVoiceOverlapWarning = null
  localViewerCount = 0
  chatMessages = []
  clearBroadcastChatState()
  clearBroadcastChatProfileCache()
  currentSessionId = null
  broadcasterIdentityForRoom = null
  studioPresentation = "hidden"
  localHandRaised = false
  raisedHandIdentities = []
  handFeedback = null
  liveParticipants = []
  interactiveProfiles = {}
  streamListenMuted = false
  viewerMicMuted = false
  speakInviteNotice = null
  viewerUserId = null
  viewerAccessToken = null
  dismissedSpeakInviteSessionId = null
  speakerUpgradeInFlight = false
  speakerGrantUserIds = []
  sessionBlockUserIds = []
  boundViewerVideoElement = null
  speakerAutoUpgradeAttemptedSessionId = null
  setBroadcastStreamListenMuted(false)
  setBroadcastPublisherCredentials(null)
  intentionalBroadcastRoomTeardown = false
}

export function subscribeTradeRoomBroadcast(listener: Listener): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getTradeRoomBroadcastSnapshot(): BroadcastStoreSnapshot {
  return snapshotCache.getSnapshot()
}

export function getTradeRoomBroadcastRoom(): Room | null {
  return broadcastRoom
}

export function setTradeRoomBroadcastStatus(next: BroadcastRoomStatus): void {
  if (
    next.broadcastSessionId &&
    currentSessionId &&
    next.broadcastSessionId !== currentSessionId
  ) {
    resetChatForNewSession(next.broadcastSessionId)
    currentSessionId = next.broadcastSessionId
  }
  if (!next.live && isWatching) {
    void teardownBroadcastRoom().then(() => emit())
  }
  status = next
  if (next.videoSource) preferredVideoSource = next.videoSource
  emit()
}

export async function refreshTradeRoomBroadcastStatus(
  fetchStatus: () => Promise<BroadcastRoomStatus>
): Promise<void> {
  try {
    const next = await fetchStatus()
    setTradeRoomBroadcastStatus(next)
    error = null
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not load stream status."
  }
  emit()
}

export async function sendTradeRoomBroadcastChatMessage(options: {
  userId: string
  displayName: string
  avatarUrl: string | null
  text: string
}): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!broadcastRoom) {
    return { ok: false, error: "Not connected to the stream." }
  }
  const result = await publishBroadcastChatMessage(broadcastRoom, options)
  if (result.ok) {
    const selfMsg = {
      id: `${options.userId}-${Date.now()}`,
      userId: options.userId,
      displayName: options.displayName,
      avatarUrl: options.avatarUrl,
      text: options.text.trim(),
      sentAt: Date.now(),
    }
    chatMessages = trimBroadcastChatMessages([...chatMessages, selfMsg])
    emit()
  }
  return result
}

export async function toggleTradeRoomBroadcastMicMuted(): Promise<void> {
  if (!broadcastRoom || role !== "broadcaster") return
  const next = !broadcasterMicMuted
  try {
    await broadcastRoom.localParticipant.setMicrophoneEnabled(!next)
    broadcasterMicMuted = next
    emit()
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not toggle microphone."
    emit()
  }
}

export function toggleTradeRoomBroadcastStreamListenMuted(): void {
  streamListenMuted = !getBroadcastStreamListenMuted()
  setBroadcastStreamListenMuted(streamListenMuted)
  emit()
}

export async function toggleTradeRoomBroadcastViewerMicMuted(): Promise<void> {
  if (!broadcastRoom || role !== "conversation") return
  const next = !viewerMicMuted
  try {
    await broadcastRoom.localParticipant.setMicrophoneEnabled(!next)
    viewerMicMuted = next
    emit()
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not toggle microphone."
    emit()
  }
}

export function dismissTradeRoomBroadcastSpeakInvite(): void {
  if (speakInviteNotice?.sessionId) {
    dismissedSpeakInviteSessionId = speakInviteNotice.sessionId
  }
  speakInviteNotice = null
  emit()
}

export async function acceptTradeRoomBroadcastSpeakInvite(options: {
  roomId: string
  videoElement: HTMLVideoElement
  accessToken: string
  fetchConversationToken: () => Promise<{
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
  }>
}): Promise<void> {
  if (speakerUpgradeInFlight || isBusy) return
  speakerUpgradeInFlight = true
  emit()
  try {
    await joinTradeRoomBroadcastConversation({
      roomId: options.roomId,
      videoElement: options.videoElement,
      fetchJoin: options.fetchConversationToken,
    })
    speakerAutoUpgradeAttemptedSessionId =
      currentSessionId ?? speakInviteNotice?.sessionId ?? null
    speakInviteNotice = null
    viewerMicMuted = false
  } catch (err) {
    error =
      err instanceof Error ? err.message : "Could not join as a speaker."
  } finally {
    speakerUpgradeInFlight = false
    emit()
  }
}

export type BroadcastGoLiveSetup = {
  videoSource: TradeRoomBroadcastVideoSource
  voiceMode: TradeRoomBroadcastVoiceMode
  enableBroadcasterMic: boolean
}

export async function startTradeRoomBroadcast(options: {
  roomId: string
  setup: BroadcastGoLiveSetup
  publisherAccessToken?: string | null
  fetchStart: () => Promise<{
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode: TradeRoomBroadcastVoiceMode
    videoSource: TradeRoomBroadcastVideoSource
  }>
  fetchStop: (sessionId: string) => Promise<void>
}): Promise<void> {
  if (isBusy) return
  isBusy = true
  error = null
  generalVoiceOverlapWarning = generalVoiceWarningIfNeeded()
  emit()

  try {
    if (broadcastRoom && roomId !== options.roomId) {
      await stopTradeRoomBroadcast({
        roomId: roomId ?? options.roomId,
        sessionId: currentSessionId ?? "",
        fetchStop: async () => {},
        skipApi: true,
      })
    }

    const start = await options.fetchStart()
    roomId = options.roomId
    resetChatForNewSession(start.broadcastSessionId)
    currentSessionId = start.broadcastSessionId
    broadcasterIdentityForRoom = start.broadcasterUserId
    preferredVideoSource = start.videoSource
    role = "broadcaster"
    isPublishing = true
    isWatching = false
    isInConversation = false
    broadcasterMicMuted = false
    broadcasterMicWarning = null

    status = {
      live: true,
      broadcastSessionId: start.broadcastSessionId,
      broadcasterUserId: start.broadcasterUserId,
      broadcasterDisplayName: start.broadcasterDisplayName,
      startedAt: start.startedAt,
      voiceMode: start.voiceMode,
      videoSource: start.videoSource,
    }

    const nextRoom = new Room({
      adaptiveStream: true,
      dynacast: true,
    })
    broadcastRoom = nextRoom

    logBroadcast("broadcaster connecting", {
      roomId: options.roomId,
      broadcastSessionId: start.broadcastSessionId,
      videoSource: start.videoSource,
      voiceMode: start.voiceMode,
    })

    await nextRoom.connect(start.livekitUrl, start.token)
    connectionState = nextRoom.state

    logBroadcast("broadcaster connected", {
      roomId: options.roomId,
      broadcastSessionId: start.broadcastSessionId,
      connectionState: nextRoom.state,
    })

    nextRoom.on(RoomEvent.LocalTrackPublished, () => {
      syncAudienceCount(nextRoom, start.broadcasterUserId)
      emit()
    })

    attachRoomSync(nextRoom, start.broadcasterUserId)
    registerChat(nextRoom)
    registerHand(nextRoom)
    studioPresentation = "studio"

    localPreviewCleanup?.()
    localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
      nextRoom,
      () => broadcasterPreviewElement,
      start.videoSource
    )

    try {
      if (start.videoSource === "camera") {
        await nextRoom.localParticipant.setCameraEnabled(true, {
          resolution: { width: 1280, height: 720, frameRate: 24 },
        })
      } else {
        await nextRoom.localParticipant.setScreenShareEnabled(true, {
          audio: false,
          selfBrowserSurface: "include",
          surfaceSwitching: "include",
        })
      }
    } catch (videoErr) {
      logBroadcast("broadcaster video publish failed", {
        roomId: options.roomId,
        message:
          videoErr instanceof Error ? videoErr.message : String(videoErr),
      })
      await options.fetchStop(start.broadcastSessionId).catch(() => {})
      await teardownBroadcastRoom()
      throw videoErr
    }

    const localPub = findLocalBroadcastVideoPublication(
      nextRoom,
      start.videoSource
    )
    if (!localPub?.track) {
      const reason =
        start.videoSource === "screen"
          ? "Screen share was cancelled or no video track was published."
          : "Camera track was not published. Check browser camera permission."
      logBroadcast("broadcaster missing local video publication", {
        roomId: options.roomId,
        reason,
      })
      await options.fetchStop(start.broadcastSessionId).catch(() => {})
      await teardownBroadcastRoom()
      throw new Error(reason)
    }

    logBroadcast("broadcaster local video published", {
      roomId: options.roomId,
      trackSource: String(localPub.source),
      trackSid: localPub.trackSid,
    })

    if (broadcasterPreviewElement) {
      const preview = syncLocalBroadcastPreviewToElement(
        nextRoom,
        broadcasterPreviewElement,
        start.videoSource
      )
      broadcasterPreviewError = preview.ok ? null : preview.reason
    }

    if (options.setup.enableBroadcasterMic) {
      try {
        await nextRoom.localParticipant.setMicrophoneEnabled(true)
        broadcasterMicMuted = false
      } catch (micErr) {
        broadcasterMicWarning =
          "Microphone unavailable — streaming video only. Check browser permissions."
        console.warn("[broadcast] mic publish failed", micErr)
      }
    }

    const localVideo = localPub.track
    localVideo?.mediaStreamTrack.addEventListener("ended", () => {
      void stopTradeRoomBroadcast({
        roomId: options.roomId,
        sessionId: start.broadcastSessionId,
        fetchStop: () => options.fetchStop(start.broadcastSessionId),
      })
    })

    if (options.publisherAccessToken) {
      setBroadcastPublisherCredentials({
        roomId: options.roomId,
        sessionId: start.broadcastSessionId,
        accessToken: options.publisherAccessToken,
      })
    }

    connectionState = nextRoom.state
    emit()
  } catch (err) {
    error = broadcastStartErrorMessage(err)
    await teardownBroadcastRoom()
    roomId = null
    emit()
  } finally {
    isBusy = false
    emit()
  }
}

async function connectBroadcastViewer(options: {
  roomId: string
  videoElement: HTMLVideoElement
  tokenPayload: {
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
  }
  asConversation: boolean
}): Promise<void> {
  const { tokenPayload } = options
  if (broadcastRoom) {
    await teardownBroadcastRoom()
  }

  resetChatForNewSession(tokenPayload.broadcastSessionId)
  currentSessionId = tokenPayload.broadcastSessionId
  roomId = options.roomId
  broadcasterIdentityForRoom = tokenPayload.broadcasterUserId
  preferredVideoSource = tokenPayload.videoSource ?? "screen"
  role = options.asConversation ? "conversation" : "viewer"
  isInConversation = options.asConversation
  isWatching = true
  isPublishing = false
  generalVoiceOverlapWarning = generalVoiceWarningIfNeeded()

  status = {
    live: true,
    broadcastSessionId: tokenPayload.broadcastSessionId,
    broadcasterUserId: tokenPayload.broadcasterUserId,
    broadcasterDisplayName: tokenPayload.broadcasterDisplayName,
    startedAt: tokenPayload.startedAt,
    voiceMode: tokenPayload.voiceMode,
    videoSource: tokenPayload.videoSource,
  }

  const nextRoom = new Room({
    adaptiveStream: true,
    dynacast: true,
  })
  broadcastRoom = nextRoom

  logBroadcast("viewer connecting", {
    roomId: options.roomId,
    broadcastSessionId: tokenPayload.broadcastSessionId,
    asConversation: options.asConversation,
    preferredVideoSource: preferredVideoSource,
  })

  await nextRoom.connect(tokenPayload.livekitUrl, tokenPayload.token)
  connectionState = nextRoom.state

  logBroadcast("viewer connected", {
    roomId: options.roomId,
    broadcastSessionId: tokenPayload.broadcastSessionId,
    connectionState: nextRoom.state,
    broadcasterIdentity: tokenPayload.broadcasterUserId,
  })

  attachRoomSync(nextRoom, tokenPayload.broadcasterUserId)
  registerChat(nextRoom)
  registerHand(nextRoom)
  boundViewerVideoElement = options.videoElement
  registerViewerMedia(
    nextRoom,
    tokenPayload.broadcasterUserId,
    options.videoElement,
    tokenPayload.voiceMode ?? "broadcast_only"
  )

  if (options.asConversation) {
    try {
      await nextRoom.localParticipant.setMicrophoneEnabled(true)
      viewerMicMuted = false
    } catch (err) {
      error = err instanceof Error ? err.message : "Could not enable microphone."
      viewerMicMuted = true
    }
    registerViewerMedia(
      nextRoom,
      tokenPayload.broadcasterUserId,
      options.videoElement,
      tokenPayload.voiceMode ?? "broadcast_only"
    )
  }

  if (viewerAccessToken) {
    startInteractivePolling(viewerAccessToken)
  }

  connectionState = nextRoom.state
  emit()
}

export async function watchTradeRoomBroadcast(options: {
  roomId: string
  videoElement: HTMLVideoElement
  accessToken?: string | null
  viewerUserId?: string | null
  fetchViewerToken: () => Promise<{
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
  }>
}): Promise<void> {
  if (isBusy) return
  if (
    isWatching &&
    !isInConversation &&
    roomId === options.roomId &&
    broadcastRoom?.state === ConnectionState.Connected &&
    currentSessionId != null &&
    broadcasterIdentityForRoom
  ) {
    reattachBroadcastVideoToElement(
      broadcastRoom,
      broadcasterIdentityForRoom,
      options.videoElement,
      preferredVideoSource
    )
    return
  }

  isBusy = true
  error = null
  emit()

  try {
    viewerUserId = options.viewerUserId ?? null
    if (options.accessToken) {
      viewerAccessToken = options.accessToken
    }
    const tokenPayload = await options.fetchViewerToken()
    await connectBroadcastViewer({
      roomId: options.roomId,
      videoElement: options.videoElement,
      tokenPayload,
      asConversation: false,
    })
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not watch the stream."
    await teardownBroadcastRoom()
    isWatching = false
    roomId = null
    emit()
  } finally {
    isBusy = false
    emit()
  }
}

export async function joinTradeRoomBroadcastConversation(options: {
  roomId: string
  videoElement: HTMLVideoElement
  fetchJoin: () => Promise<{
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
  }>
}): Promise<void> {
  if (isBusy) return
  isBusy = true
  error = null
  emit()

  try {
    const tokenPayload = await options.fetchJoin()
    await connectBroadcastViewer({
      roomId: options.roomId,
      videoElement: options.videoElement,
      tokenPayload,
      asConversation: true,
    })
  } catch (err) {
    error =
      err instanceof Error ? err.message : "Could not join the conversation."
    emit()
  } finally {
    isBusy = false
    emit()
  }
}

export async function leaveTradeRoomBroadcastConversation(options: {
  roomId: string
  videoElement: HTMLVideoElement
  fetchLeave: () => Promise<{
    viewerToken: {
      token: string
      livekitUrl: string
      broadcastSessionId: string
      broadcasterUserId: string
      broadcasterDisplayName: string | null
      startedAt: string
      voiceMode?: TradeRoomBroadcastVoiceMode
      videoSource?: TradeRoomBroadcastVideoSource
    } | null
  }>
}): Promise<void> {
  if (isBusy) return
  isBusy = true
  emit()

  try {
    const leave = await options.fetchLeave()
    const viewer = leave.viewerToken
    if (!viewer?.token) {
      isInConversation = false
      role = "viewer"
      if (broadcastRoom) {
        await broadcastRoom.localParticipant.setMicrophoneEnabled(false)
      }
      emit()
      return
    }
    await connectBroadcastViewer({
      roomId: options.roomId,
      videoElement: options.videoElement,
      tokenPayload: {
        token: viewer.token,
        livekitUrl: viewer.livekitUrl,
        broadcastSessionId: viewer.broadcastSessionId ?? currentSessionId ?? "",
        broadcasterUserId:
          viewer.broadcasterUserId ?? broadcasterIdentityForRoom ?? "",
        broadcasterDisplayName: viewer.broadcasterDisplayName ?? null,
        startedAt: viewer.startedAt ?? new Date().toISOString(),
        voiceMode: viewer.voiceMode,
        videoSource: viewer.videoSource,
      },
      asConversation: false,
    })
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not leave conversation."
    emit()
  } finally {
    isBusy = false
    emit()
  }
}

export async function stopTradeRoomBroadcast(options: {
  roomId: string
  sessionId: string
  fetchStop: () => Promise<void>
  skipApi?: boolean
}): Promise<void> {
  isBusy = true
  emit()

  try {
    if (!options.skipApi && options.sessionId) {
      await options.fetchStop()
    }
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not stop the stream."
  } finally {
    await teardownBroadcastRoom()
    status = { live: false }
    roomId = null
    isBusy = false
    emit()
  }
}

export async function leaveTradeRoomBroadcastViewer(): Promise<void> {
  await teardownBroadcastRoom()
  isWatching = false
  role = "none"
  roomId = null
  emit()
}

/** Call when the viewer <video> element mounts or changes. */
export function getTradeRoomBroadcastViewerVideoElement(): HTMLVideoElement | null {
  return boundViewerVideoElement
}

export function syncTradeRoomBroadcastViewerVideoElement(
  videoElement: HTMLVideoElement
): void {
  boundViewerVideoElement = videoElement
  if (!broadcastRoom || !broadcasterIdentityForRoom || !isWatching) return
  if (role !== "viewer" && role !== "conversation") return
  reattachBroadcastVideoToElement(
    broadcastRoom,
    broadcasterIdentityForRoom,
    videoElement,
    preferredVideoSource
  )
}

/** Broadcaster local preview — uses published local track, not remote subscription. */
export function syncTradeRoomBroadcastLocalPreviewElement(
  videoElement: HTMLVideoElement
): void {
  broadcasterPreviewElement = videoElement
  if (!broadcastRoom || role !== "broadcaster" || !isPublishing) return
  const preview = syncLocalBroadcastPreviewToElement(
    broadcastRoom,
    videoElement,
    preferredVideoSource
  )
  broadcasterPreviewError = preview.ok ? null : preview.reason
  emit()
}

export function getTradeRoomBroadcastLocalPreviewError(): string | null {
  return broadcasterPreviewError
}
