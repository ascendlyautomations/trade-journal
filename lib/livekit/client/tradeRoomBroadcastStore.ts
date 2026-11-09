"use client"

import {
  ConnectionState,
  RemoteParticipant,
  Room,
  RoomEvent,
  Track,
} from "livekit-client"
import { createExternalStoreSnapshotCache } from "./externalStoreSnapshot.ts"
import { classifyViewerBroadcastDisconnect } from "./tradeRoomBroadcastViewerDisconnect.ts"
import { runSingleFlightByKey } from "./runSingleFlightByKey.ts"
import {
  broadcastStartErrorMessage,
  BroadcastNoActiveStreamError,
} from "./tradeRoomBroadcastErrors.ts"
import {
  getBroadcastPublisherCredentials,
  setBroadcastPublisherCredentials,
} from "./tradeRoomBroadcastPublisherLifecycle.ts"
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
  detachObsIngressVideoTracksFromElement,
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
import {
  DEFAULT_SCREEN_CAMERA_OVERLAY_POSITION,
  type ScreenCameraOverlayPosition,
} from "./tradeRoomBroadcastScreenOverlayTypes.ts"
import {
  disableScreenCameraOverlay,
  enableScreenCameraOverlay,
  getScreenOverlayRawScreenTrack,
  getScreenOverlaySessionActive,
  releaseBrowserScreenShareCapture,
  setScreenCameraOverlayPosition,
  setScreenOverlayCameraVisible,
  stopScreenCameraOverlaySession,
} from "./tradeRoomBroadcastScreenOverlaySession.ts"
import {
  isBroadcastScreenShareCancelled,
  tradeRoomBroadcastScreenShareProgramActive,
  tradeRoomBroadcastShareScreenWhileLiveAvailable,
} from "./tradeRoomBroadcastScreenShareWhileLive.ts"
import {
  clearBroadcastChatProfileCache,
  normalizeBroadcastChatAvatarUrl,
} from "./tradeRoomBroadcastChatProfiles.ts"
import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "../tradeRoomBroadcastVoiceMode.ts"
import {
  isObsIngressPublisherIdentity,
  primaryMediaPublisherIdentityForBroadcastSession,
} from "../tradeRoomBroadcastObsIdentity.ts"
import {
  getTradeRoomLiveVoiceSnapshot,
  leaveTradeRoomLiveVoice,
} from "./tradeRoomLiveVoiceStore.ts"
import {
  declineBroadcastSpeakInvite,
  fetchBroadcastAcceptSpeakInvitePayload,
} from "./tradeRoomBroadcastInviteRespond.ts"
import { fetchBroadcastConversationJoinPayload } from "./tradeRoomBroadcastJoinConversation.ts"
import { resolveBroadcastLiveVisibility } from "./broadcastVisibilityMerge.ts"

export type BroadcastSource = "browser" | "obs"

export type BroadcastRoomStatus = {
  live: boolean
  /**
   * Discoverable / viewer-accessible live. False during OBS private preparation
   * even though `live` may still describe an active session row for the host.
   */
  publicLive?: boolean
  /** preparing = host-only OBS setup; public = viewers allowed. */
  visibility?: "public" | "preparing"
  broadcastSessionId?: string
  broadcasterUserId?: string
  broadcasterDisplayName?: string | null
  startedAt?: string
  viewerCount?: number | null
  voiceMode?: TradeRoomBroadcastVoiceMode
  videoSource?: TradeRoomBroadcastVideoSource
  /** browser = WebRTC host; obs = primary program via LiveKit Ingress (Phase 2 playback). */
  broadcastSource?: BroadcastSource
  /** LiveKit identity for OBS program media when broadcastSource is obs. */
  primaryMediaPublisherIdentity?: string | null
  livekitIngressId?: string | null
  ingressStatusSnapshot?: string | null
  /** Host (broadcaster_user_id) connected in the broadcast LiveKit room. */
  hostConnected?: boolean | null
  /** OBS / ingress publisher connected. */
  primaryMediaPublisherConnected?: boolean | null
  broadcasterConnected?: boolean | null
  alreadyLiveElsewhere?: boolean
}

export type BroadcastRole = "none" | "broadcaster" | "viewer" | "conversation"

export type BroadcastStudioPresentation = "hidden" | "studio" | "mini"

/**
 * Stable host-only OBS UI phase (derived; not inferred from transient bootstrapping alone).
 * `null` when this client is not the OBS host publisher.
 */
export type BroadcastObsHostUiPhase =
  | "idle"
  | "preparing"
  | "waiting_for_encoder"
  | "preview_ready"
  | "publishing"
  | "public"
  | "error"

/** OBS host studio: stream key is kept in module memory until session ends (not persisted). */
export type ObsStudioState = {
  phase:
    | "off"
    | "creating_ingress"
    | "waiting_for_obs"
    | "connecting"
    | "preview_ready"
    | "live"
    | "encoder_disconnected"
    | "reconnecting"
    | "ended"
  rtmpUrl: string | null
  /** Populated only while the host has chosen to reveal the key in UI. */
  revealedStreamKey: string | null
  /** True after successful ingress attach (duplicate create blocked server-side). */
  hasIngressCredentials: boolean
  credentialsBusy: boolean
  /**
   * True when the server reports ingress attached but RTMP/key are not in this tab's memory
   * (e.g. duplicate request, or refresh). Use Regenerate to mint new credentials.
   */
  credentialsLostOrUnavailable: boolean
  /** Safe error when credential creation failed (never includes stream key). */
  credentialsError: string | null
}

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
  /** Conversation role: true once a microphone track is actually published to the room. */
  viewerMicPublishReady: boolean
  speakInviteNotice: BroadcastSpeakInviteNotice | null
  viewerUserId: string | null
  speakerGrantUserIds: string[]
  sessionBlockUserIds: string[]
  viewerStreamRemovalNotice: BroadcastViewerStreamRemovalNotice | null
  viewerBroadcastConnectionLost: BroadcastViewerConnectionLost | null
  speakerUpgradeInFlight: boolean
  obsStudio: ObsStudioState | null
  /** True only while OBS private session is being started (before isPublishing). */
  obsBroadcastBootstrapping: boolean
  /** Host OBS flow only; null for viewers or browser broadcasters. */
  obsHostUiPhase: BroadcastObsHostUiPhase | null
  /** Active publisher session id (module); use to ignore stale status for another session. */
  publisherSessionId: string | null
  /** Screen/camera capture ended or failed while session still active (retry without ending). */
  publisherCaptureDegraded: boolean
  /** Browser screen share: canvas compositor webcam PiP is active. */
  screenCameraOverlayEnabled: boolean
  screenCameraOverlayCameraVisible: boolean
  screenCameraOverlayPosition: ScreenCameraOverlayPosition
  screenCameraOverlayBusy: boolean
  screenCameraOverlayError: string | null
  screenShareWhileLiveBusy: boolean
  screenShareWhileLiveError: string | null
}

export type BroadcastViewerStreamRemovalNotice = {
  kind: "removed" | "banned"
  sessionId: string
}

export type BroadcastViewerConnectionLost = {
  roomId: string
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

/** Clients that need interactive-state polling; only one shared timer runs in the store. */
export type BroadcastInteractivePollOwner =
  | "viewer-session"
  | "passive-panel"
  | "host-studio"
  | "global-studio"

const BROADCAST_INTERACTIVE_POLL_MS = 4000

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
let viewerMicPublishReady = false
let speakInviteNotice: BroadcastSpeakInviteNotice | null = null
let viewerUserId: string | null = null
let viewerAccessToken: string | null = null
let dismissedSpeakInviteSessionId: string | null = null
let speakerUpgradeInFlight = false
let interactivePollTimer: ReturnType<typeof setInterval> | null = null
const interactivePollOwners = new Set<BroadcastInteractivePollOwner>()
let interactivePollAccessToken: string | null = null
let viewerStatusRefreshTimer: ReturnType<typeof setTimeout> | null = null
let viewerStatusRefreshInFlight = false
let speakerGrantUserIds: string[] = []
let sessionBlockUserIds: string[] = []
let boundViewerVideoElement: HTMLVideoElement | null = null
let broadcasterPreviewElement: HTMLVideoElement | null = null
let broadcasterPreviewError: string | null = null
let currentSessionId: string | null = null
let publisherCaptureDegraded = false
let preferredVideoSource: TradeRoomBroadcastVideoSource = "screen"
let screenCameraOverlayEnabled = false
let screenCameraOverlayCameraVisible = false
let screenCameraOverlayPosition: ScreenCameraOverlayPosition =
  DEFAULT_SCREEN_CAMERA_OVERLAY_POSITION
let screenCameraOverlayBusy = false
let screenCameraOverlayError: string | null = null
let screenShareWhileLiveBusy = false
let screenShareWhileLiveError: string | null = null

const BROWSER_SCREEN_SHARE_OPTS = {
  audio: false,
  selfBrowserSurface: "include" as const,
  surfaceSwitching: "include" as const,
}

export {
  tradeRoomBroadcastScreenShareProgramActive,
  tradeRoomBroadcastShareScreenWhileLiveAvailable,
} from "./tradeRoomBroadcastScreenShareWhileLive.ts"
let broadcasterIdentityForRoom: string | null = null
let viewerStreamRemovalNotice: BroadcastViewerStreamRemovalNotice | null = null
let viewerBroadcastConnectionLost: BroadcastViewerConnectionLost | null = null
let intentionalBroadcastRoomTeardown = false
let viewerRemovalHandling = false
let passiveInteractiveContext: BroadcastPassiveInteractiveContext | null = null
let speakerAutoUpgradeAttemptedSessionId: string | null = null
/** Broadcaster: play remote guest microphones (invite / open voice). */
let broadcasterRemoteSpeakerAudioCleanup: (() => void) | null = null
/** Conversation viewer: listeners for LocalTrackPublished to sync viewerMicPublishReady. */
let conversationMicStateCleanup: (() => void) | null = null

/** Session-scoped program publisher (OBS) — module memory only. */
let activeBroadcastSource: BroadcastSource | null = null
let activePrimaryMediaPublisherIdentity: string | null = null
let obsRtmpUrlMemory: string | null = null
let obsStreamKeyMemory: string | null = null
let obsStreamKeyRevealed = false
let obsCredentialsBusy = false
let obsHasIngressCredentials = false
/** Server has ingress for this session but this tab lost the secret RTMP payload. */
let obsCredentialsLostOrUnavailable = false
let obsCredentialsError: string | null = null
/** One credential HTTP sequence in flight per broadcast session id. */
const obsCredentialsFlightBySession = new Map<string, Promise<unknown>>()
/** Host wanted mic for moderation; for OBS we enable after public go-live so prep UI stays minimal. */
let obsDeferredEnableHostMic = false
let obsBroadcastBootstrapping = false
let obsPublishRequestInFlight = false

function computeObsHostUiPhase(): BroadcastObsHostUiPhase | null {
  if (!isPublishing || role !== "broadcaster") return null
  if (status.videoSource !== "obs") return null
  if (obsPublishRequestInFlight) return "publishing"
  if (status.publicLive === true) return "public"
  const hasRecoverableCredentialIssue =
    Boolean(obsCredentialsError?.trim()) &&
    !obsHasIngressCredentials &&
    !obsCredentialsBusy
  if (hasRecoverableCredentialIssue) {
    return "error"
  }
  if (obsBroadcastBootstrapping) return "preparing"
  if (obsCredentialsBusy || !obsHasIngressCredentials) return "preparing"
  if (status.primaryMediaPublisherConnected !== true) {
    return "waiting_for_encoder"
  }
  return "preview_ready"
}

/** DB row + status can lag; `video_source === "obs"` is authoritative for encoder sessions. */
function resolveEffectiveBroadcastMode(): BroadcastSource {
  if (status.videoSource === "obs") return "obs"
  const bs = status.broadcastSource ?? activeBroadcastSource
  return bs === "obs" ? "obs" : "browser"
}

function buildObsStudioSnapshot(): ObsStudioState | null {
  if (resolveEffectiveBroadcastMode() !== "obs" || !isPublishing) return null
  const hostConn = status.hostConnected
  const primaryConn = status.primaryMediaPublisherConnected
  const publicLive = status.publicLive === true
  const ingressWaiting =
    status.ingressStatusSnapshot === "ENDPOINT_INACTIVE" ||
    status.ingressStatusSnapshot === "ENDPOINT_BUFFERING"
  let phase: ObsStudioState["phase"] = "connecting"
  if (obsCredentialsBusy) phase = "creating_ingress"
  else if (
    !obsHasIngressCredentials &&
    !obsCredentialsError &&
    !obsCredentialsLostOrUnavailable
  ) {
    phase = "creating_ingress"
  }
  else if (connectionState === ConnectionState.Reconnecting) phase = "reconnecting"
  else if (!primaryConn && ingressWaiting) phase = "waiting_for_obs"
  else if (!primaryConn && hostConn) phase = "encoder_disconnected"
  else if (primaryConn && !publicLive) phase = "preview_ready"
  else if (primaryConn && publicLive) phase = "live"
  else if (connectionState === ConnectionState.Connecting) phase = "connecting"
  return {
    phase,
    rtmpUrl: obsRtmpUrlMemory,
    revealedStreamKey: obsStreamKeyRevealed ? obsStreamKeyMemory : null,
    hasIngressCredentials: obsHasIngressCredentials,
    credentialsBusy: obsCredentialsBusy,
    credentialsLostOrUnavailable: obsCredentialsLostOrUnavailable,
    credentialsError: obsCredentialsError,
  }
}

function resetObsCredentialMemory(): void {
  obsRtmpUrlMemory = null
  obsStreamKeyMemory = null
  obsStreamKeyRevealed = false
  obsCredentialsBusy = false
  obsHasIngressCredentials = false
  obsCredentialsLostOrUnavailable = false
  obsCredentialsError = null
}

function clearObsStudioMemory(): void {
  resetObsCredentialMemory()
  obsDeferredEnableHostMic = false
  activeBroadcastSource = null
  activePrimaryMediaPublisherIdentity = null
}

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
    viewerMicPublishReady,
    speakInviteNotice,
    viewerUserId,
    speakerGrantUserIds,
    sessionBlockUserIds,
    viewerStreamRemovalNotice,
    viewerBroadcastConnectionLost,
    speakerUpgradeInFlight,
    obsStudio: buildObsStudioSnapshot(),
    obsBroadcastBootstrapping,
    obsHostUiPhase: computeObsHostUiPhase(),
    publisherSessionId: currentSessionId,
    publisherCaptureDegraded,
    screenCameraOverlayEnabled,
    screenCameraOverlayCameraVisible,
    screenCameraOverlayPosition,
    screenCameraOverlayBusy,
    screenCameraOverlayError,
    screenShareWhileLiveBusy,
    screenShareWhileLiveError,
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
  localViewerCount = countBroadcastAudience(
    activeRoom,
    broadcasterId,
    activeBroadcastSource === "obs" ? activePrimaryMediaPublisherIdentity : null
  )
}

function syncLiveParticipantRoster(activeRoom: Room, broadcasterId: string) {
  const roster: BroadcastLiveParticipant[] = []
  const seen = new Set<string>()
  const programId = activePrimaryMediaPublisherIdentity?.trim() || ""

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

  if (
    activeBroadcastSource === "obs" &&
    programId &&
    activeRoom.remoteParticipants.has(programId)
  ) {
    const obsP = activeRoom.remoteParticipants.get(programId)
    pushParticipant(
      programId,
      obsP?.name?.trim() || "OBS",
      false
    )
  }

  for (const participant of activeRoom.remoteParticipants.values()) {
    const userId = participant.identity
    if (userId === programId) continue
    pushParticipant(
      userId,
      participant.name?.trim() || "Member",
      userId === broadcasterId
    )
  }

  liveParticipants = roster
}

function resolveProgramPublisherIdentityForSignals(): string {
  const bs = resolveEffectiveBroadcastMode()
  if (bs === "obs") {
    return (
      status.primaryMediaPublisherIdentity?.trim() ||
      activePrimaryMediaPublisherIdentity?.trim() ||
      ""
    )
  }
  return broadcasterIdentityForRoom?.trim() || ""
}

function maybeScheduleViewerBroadcastStatusRefresh(
  disconnectedIdentity: string,
  broadcasterId: string
): void {
  if (isPublishing || intentionalBroadcastRoomTeardown) return
  if (!isWatching && role !== "viewer" && role !== "conversation") return
  const hostId = broadcasterId.trim()
  const programId = resolveProgramPublisherIdentityForSignals()
  const leftId = disconnectedIdentity.trim()
  if (!leftId) return
  if (leftId !== hostId && !(programId && leftId === programId)) return
  scheduleViewerBroadcastStatusRefresh()
}

function attachRoomSync(activeRoom: Room, broadcasterId: string) {
  const sync = () => {
    connectionState = activeRoom.state
    if (
      isPublishing &&
      (activeRoom.state === ConnectionState.Disconnected ||
        activeRoom.state === ConnectionState.Reconnecting)
    ) {
      if (
        activeRoom.state === ConnectionState.Disconnected &&
        !intentionalBroadcastRoomTeardown
      ) {
        broadcasterPreviewError =
          broadcasterPreviewError ??
          "LiveKit disconnected. You can retry or end the stream."
      }
    }
    syncAudienceCount(activeRoom, broadcasterId)
    syncLiveParticipantRoster(activeRoom, broadcasterId)
    emit()
  }
  const onParticipantDisconnected = (participant: RemoteParticipant) => {
    sync()
    maybeScheduleViewerBroadcastStatusRefresh(
      participant.identity,
      broadcasterId
    )
  }
  activeRoom.on(RoomEvent.ConnectionStateChanged, sync)
  activeRoom.on(RoomEvent.ParticipantConnected, sync)
  activeRoom.on(RoomEvent.ParticipantDisconnected, onParticipantDisconnected)
  activeRoom.on(RoomEvent.Disconnected, () => {
    void handleViewerBroadcastLiveKitDisconnected()
  })
  sync()
}

async function handleViewerBroadcastLiveKitDisconnected(): Promise<void> {
  if (
    isPublishing ||
    intentionalBroadcastRoomTeardown ||
    speakerUpgradeInFlight
  ) {
    return
  }
  if (!isWatching && role !== "viewer" && role !== "conversation") return
  if (viewerRemovalHandling) return

  const watchingSessionId = currentSessionId ?? ""
  const activeRoomId = roomId
  const token = viewerAccessToken?.trim() ?? interactivePollAccessToken?.trim()
  if (!watchingSessionId || !activeRoomId) return

  viewerRemovalHandling = true
  try {
    if (token) {
      try {
        const res = await fetch(
          `/api/livekit/broadcast/status?roomId=${encodeURIComponent(activeRoomId)}&reconcile=1`,
          { headers: { Authorization: `Bearer ${token}` } }
        )
        const payload = (await res.json().catch(() => ({}))) as Record<
          string,
          unknown
        >
        if (!res.ok) {
          if (res.status === 404 || payload.live === false) {
            setTradeRoomBroadcastStatus({ live: false, publicLive: false })
          }
        } else {
          setTradeRoomBroadcastStatus(statusPayloadFromApiJson(payload))
        }
      } catch {
        // Use last known status + interactive snapshot below.
      }
    }

    let interactiveSnapshot:
      | {
          sessionId?: string
          blockedFromBroadcastRejoin?: boolean
          presentInLiveKitBroadcastRoom?: boolean
          sessionBlocks?: string[]
        }
      | null
      | undefined = null

    if (token) {
      try {
        const res = await fetch(
          `/api/livekit/broadcast/interactive-state?roomId=${encodeURIComponent(activeRoomId)}`,
          { headers: { Authorization: `Bearer ${token}` } }
        )
        if (res.ok) {
          const payload = (await res.json()) as {
            snapshot?: {
              sessionId?: string
              blockedFromBroadcastRejoin?: boolean
              presentInLiveKitBroadcastRoom?: boolean
              sessionBlocks?: string[]
            } | null
          }
          interactiveSnapshot = payload.snapshot
        }
      } catch {
        interactiveSnapshot = undefined
      }
    }

    const action = classifyViewerBroadcastDisconnect({
      watchingSessionId,
      statusLive: status.live === true,
      statusSessionId: status.broadcastSessionId,
      snapshot: interactiveSnapshot,
      viewerUserId: viewerUserId ?? null,
    })

    switch (action.type) {
      case "stream_ended":
        viewerBroadcastConnectionLost = null
        await teardownBroadcastRoom({ preserveViewerCredentials: true })
        break
      case "removed":
        viewerBroadcastConnectionLost = null
        await forceViewerOffStream({
          kind: action.blocked ? "banned" : "removed",
          sessionId: watchingSessionId,
        })
        break
      case "connection_lost":
        viewerBroadcastConnectionLost = {
          roomId: activeRoomId,
          sessionId: watchingSessionId,
        }
        error = "Connection to the livestream was lost."
        await teardownBroadcastRoom({ preserveViewerCredentials: true })
        emit()
        break
    }
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

export function acknowledgeViewerBroadcastConnectionLost(): void {
  viewerBroadcastConnectionLost = null
  error = null
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

export function setBroadcastInteractivePollDemand(
  owner: BroadcastInteractivePollOwner,
  wantsPoll: boolean,
  accessToken?: string | null
): void {
  if (wantsPoll) {
    interactivePollOwners.add(owner)
    const token = accessToken?.trim()
    if (token) {
      interactivePollAccessToken = token
    } else if (viewerAccessToken?.trim()) {
      interactivePollAccessToken = viewerAccessToken.trim()
    }
  } else {
    interactivePollOwners.delete(owner)
  }
  reconcileBroadcastInteractivePolling()
}

function reconcileBroadcastInteractivePolling(): void {
  const token = interactivePollAccessToken?.trim()
  if (interactivePollOwners.size > 0 && token) {
    startInteractivePolling(token)
  } else {
    stopInteractivePolling()
  }
}

function statusPayloadFromApiJson(payload: Record<string, unknown>): BroadcastRoomStatus {
  return {
    live: Boolean(payload.live),
    publicLive:
      typeof payload.publicLive === "boolean" ? payload.publicLive : undefined,
    visibility:
      payload.visibility === "public" || payload.visibility === "preparing"
        ? payload.visibility
        : undefined,
    broadcastSessionId:
      typeof payload.broadcastSessionId === "string"
        ? payload.broadcastSessionId
        : undefined,
    broadcasterUserId:
      typeof payload.broadcasterUserId === "string"
        ? payload.broadcasterUserId
        : undefined,
    broadcasterDisplayName:
      typeof payload.broadcasterDisplayName === "string"
        ? payload.broadcasterDisplayName
        : payload.broadcasterDisplayName === null
          ? null
          : undefined,
    startedAt: typeof payload.startedAt === "string" ? payload.startedAt : undefined,
    viewerCount:
      typeof payload.viewerCount === "number" ? payload.viewerCount : undefined,
    voiceMode:
      payload.voiceMode === "open_voice" || payload.voiceMode === "broadcast_only"
        ? payload.voiceMode
        : undefined,
    videoSource:
      payload.videoSource === "screen" ||
      payload.videoSource === "camera" ||
      payload.videoSource === "obs"
        ? payload.videoSource
        : undefined,
    broadcastSource:
      payload.broadcastSource === "browser" || payload.broadcastSource === "obs"
        ? payload.broadcastSource
        : undefined,
    primaryMediaPublisherIdentity:
      typeof payload.primaryMediaPublisherIdentity === "string"
        ? payload.primaryMediaPublisherIdentity
        : payload.primaryMediaPublisherIdentity === null
          ? null
          : undefined,
    livekitIngressId:
      typeof payload.livekitIngressId === "string"
        ? payload.livekitIngressId
        : payload.livekitIngressId === null
          ? null
          : undefined,
    ingressStatusSnapshot:
      typeof payload.ingressStatusSnapshot === "string"
        ? payload.ingressStatusSnapshot
        : payload.ingressStatusSnapshot === null
          ? null
          : undefined,
    hostConnected:
      typeof payload.hostConnected === "boolean" ? payload.hostConnected : undefined,
    primaryMediaPublisherConnected:
      typeof payload.primaryMediaPublisherConnected === "boolean"
        ? payload.primaryMediaPublisherConnected
        : undefined,
    broadcasterConnected:
      typeof payload.broadcasterConnected === "boolean"
        ? payload.broadcasterConnected
        : undefined,
    alreadyLiveElsewhere:
      payload.alreadyLiveElsewhere === true ? true : undefined,
  }
}

function isLiteBroadcastStatusPayload(next: BroadcastRoomStatus): boolean {
  if (!next.live || !next.broadcastSessionId) return false
  return (
    next.broadcasterConnected === undefined &&
    next.hostConnected === undefined &&
    next.primaryMediaPublisherConnected === undefined &&
    next.viewerCount === undefined &&
    next.broadcasterDisplayName === undefined &&
    next.ingressStatusSnapshot === undefined &&
    next.livekitIngressId === undefined &&
    next.alreadyLiveElsewhere === undefined
  )
}

function scheduleViewerBroadcastStatusRefresh(): void {
  if (viewerStatusRefreshTimer) {
    clearTimeout(viewerStatusRefreshTimer)
  }
  viewerStatusRefreshTimer = setTimeout(() => {
    viewerStatusRefreshTimer = null
    void refreshBroadcastStatusAfterViewerSignal()
  }, 400)
}

async function refreshBroadcastStatusAfterViewerSignal(): Promise<void> {
  const token = viewerAccessToken?.trim() ?? interactivePollAccessToken?.trim()
  const effectiveRoomId = roomId ?? passiveInteractiveContext?.roomId
  if (!token || !effectiveRoomId || isPublishing) return

  if (viewerStatusRefreshInFlight) return
  viewerStatusRefreshInFlight = true
  try {
    const res = await fetch(
      `/api/livekit/broadcast/status?roomId=${encodeURIComponent(effectiveRoomId)}&reconcile=1`,
      { headers: { Authorization: `Bearer ${token}` } }
    )
    const payload = (await res.json().catch(() => ({}))) as Record<string, unknown>
    if (!res.ok) {
      if (res.status === 404 || payload.live === false) {
        setTradeRoomBroadcastStatus({ live: false, publicLive: false })
      }
      return
    }
    setTradeRoomBroadcastStatus(statusPayloadFromApiJson(payload))
  } catch {
    // Next LiveKit signal or panel poll will retry.
  } finally {
    viewerStatusRefreshInFlight = false
  }
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
    if (!res.ok) {
      // Legacy: server used 404 when no stream; treat like inactive snapshot.
      if (res.status === 404) {
        raisedHandIdentities = []
        speakerGrantUserIds = []
        sessionBlockUserIds = []
        speakInviteNotice = null
        interactiveProfiles = {}
        if (broadcastRoom && broadcasterIdentityForRoom) {
          syncLiveParticipantRoster(broadcastRoom, broadcasterIdentityForRoom)
        }
        emit()
        void refreshBroadcastStatusAfterViewerSignal()
      }
      return
    }
    const payload = (await res.json()) as {
      snapshot?: {
        sessionId?: string
        raisedHands?: Array<{ userId: string }>
        speakerGrants?: string[]
        sessionBlocks?: string[]
        removedFromStream?: boolean
        blockedFromBroadcastRejoin?: boolean
        pendingInvitationForViewer?: { invitationId: string } | null
      } | null
      profiles?: Array<{
        userId: string
        username: string | null
        displayName: string | null
        avatarUrl: string | null
      }>
    }

    if (payload.snapshot == null) {
      raisedHandIdentities = []
      speakerGrantUserIds = []
      sessionBlockUserIds = []
      speakInviteNotice = null
      interactiveProfiles = {}
      if (broadcastRoom && broadcasterIdentityForRoom) {
        syncLiveParticipantRoster(broadcastRoom, broadcasterIdentityForRoom)
      }
      emit()
      void refreshBroadcastStatusAfterViewerSignal()
      return
    }

    raisedHandIdentities = (payload.snapshot?.raisedHands ?? []).map((h) => h.userId)
    const sessionId = payload.snapshot?.sessionId ?? currentSessionId
    const grants = payload.snapshot?.speakerGrants ?? []
    speakerGrantUserIds = grants
    sessionBlockUserIds = payload.snapshot?.sessionBlocks ?? []
    const pendingInvite = payload.snapshot?.pendingInvitationForViewer
    if (
      payload.snapshot?.blockedFromBroadcastRejoin === true &&
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
        avatarUrl: normalizeBroadcastChatAvatarUrl(profile.avatarUrl),
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
  const activeRoomId = roomId
  const videoElement = boundViewerVideoElement
  const token = accessToken.trim()
  if (speakerUpgradeInFlight || isBusy || !activeRoomId || !videoElement) {
    return
  }
  if (!token) {
    error = "Sign in to join as a speaker."
    emit()
    return
  }
  const inviteId = speakInviteNotice?.invitationId?.trim() ?? ""
  speakerAutoUpgradeAttemptedSessionId = sessionId
  speakerUpgradeInFlight = true
  emit()
  try {
    await joinTradeRoomBroadcastConversation({
      roomId: activeRoomId,
      videoElement,
      fetchJoin: () =>
        inviteId
          ? fetchBroadcastAcceptSpeakInvitePayload(token, inviteId)
          : fetchBroadcastConversationJoinPayload(token, activeRoomId),
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
  const token = accessToken.trim()
  if (!token) return
  if (interactivePollTimer && interactivePollAccessToken === token) {
    return
  }
  stopInteractivePolling()
  interactivePollAccessToken = token
  if (!viewerAccessToken?.trim()) {
    viewerAccessToken = token
  }
  void refreshBroadcastInteractiveState(token)
  interactivePollTimer = setInterval(() => {
    void refreshBroadcastInteractiveState(token)
  }, BROADCAST_INTERACTIVE_POLL_MS)
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

function syncViewerMicPublishReady(activeRoom: Room): void {
  if (role !== "conversation") {
    viewerMicPublishReady = false
    return
  }
  let hasMic = false
  for (const pub of activeRoom.localParticipant.audioTrackPublications.values()) {
    if (pub.source !== Track.Source.Microphone) continue
    if (pub.track) {
      hasMic = true
      break
    }
  }
  viewerMicPublishReady = hasMic
}

function registerConversationMicPublishListeners(activeRoom: Room): void {
  conversationMicStateCleanup?.()
  const bump = () => {
    syncViewerMicPublishReady(activeRoom)
    emit()
  }
  activeRoom.on(RoomEvent.LocalTrackPublished, bump)
  activeRoom.on(RoomEvent.LocalTrackUnpublished, bump)
  activeRoom.on(RoomEvent.TrackMuted, bump)
  activeRoom.on(RoomEvent.TrackUnmuted, bump)
  syncViewerMicPublishReady(activeRoom)
  conversationMicStateCleanup = () => {
    activeRoom.off(RoomEvent.LocalTrackPublished, bump)
    activeRoom.off(RoomEvent.LocalTrackUnpublished, bump)
    activeRoom.off(RoomEvent.TrackMuted, bump)
    activeRoom.off(RoomEvent.TrackUnmuted, bump)
    conversationMicStateCleanup = null
  }
}

function registerViewerMedia(
  activeRoom: Room,
  broadcasterId: string,
  videoElement: HTMLVideoElement,
  voiceMode: TradeRoomBroadcastVoiceMode
) {
  logBroadcast("registerViewerMedia", {
    role,
    voiceMode,
    broadcastSource: resolveEffectiveBroadcastMode(),
    sessionIdTail: currentSessionId?.slice(-8) ?? null,
  })
  videoCleanup?.()
  audioCleanup?.()
  const bs = resolveEffectiveBroadcastMode()
  const primaryId =
    bs === "obs"
      ? status.primaryMediaPublisherIdentity ?? activePrimaryMediaPublisherIdentity
      : status.primaryMediaPublisherIdentity ?? null
  const pubPreferred: TradeRoomBroadcastVideoSource =
    preferredVideoSource === "obs" ? "screen" : preferredVideoSource

  videoCleanup = registerBroadcastVideoHandlers(activeRoom, {
    broadcastSource: bs,
    primaryMediaPublisherIdentity: primaryId,
    broadcasterUserId: broadcasterId,
    preferredSource: pubPreferred,
    getVideoElement: () => {
      if (role === "broadcaster" && bs === "obs") {
        return broadcasterPreviewElement
      }
      return boundViewerVideoElement ?? videoElement
    },
  })
  activeBroadcastSource = bs
  activePrimaryMediaPublisherIdentity = primaryId
  audioCleanup = registerBroadcastRemoteAudioHandlers(activeRoom, {
    broadcasterUserId: broadcasterId,
    broadcastSource: bs,
    primaryMediaPublisherIdentity: primaryId,
  })
}

function registerBroadcasterRemoteSpeakerAudio(activeRoom: Room, broadcasterId: string) {
  broadcasterRemoteSpeakerAudioCleanup?.()
  const bs = resolveEffectiveBroadcastMode()
  const primaryId =
    bs === "obs"
      ? status.primaryMediaPublisherIdentity ?? activePrimaryMediaPublisherIdentity
      : status.primaryMediaPublisherIdentity ?? activePrimaryMediaPublisherIdentity
  broadcasterRemoteSpeakerAudioCleanup = registerBroadcastRemoteAudioHandlers(
    activeRoom,
    {
      broadcasterUserId: broadcasterId,
      broadcastSource: bs,
      primaryMediaPublisherIdentity: primaryId,
    }
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

async function teardownBroadcastRoom(options?: {
  preserveViewerCredentials?: boolean
}) {
  const preserveViewer = options?.preserveViewerCredentials === true
  const room = broadcastRoom
  let screenCaptureReleased = false
  const ensureScreenCaptureReleased = async () => {
    if (screenCaptureReleased) return
    screenCaptureReleased = true
    await releaseBrowserScreenShareCapture(room, {
      stopDisplayCapture: true,
    }).catch(() => {})
  }
  try {
  intentionalBroadcastRoomTeardown = true
  clearObsStudioMemory()
  await ensureScreenCaptureReleased()
  screenCameraOverlayEnabled = false
  screenCameraOverlayCameraVisible = false
  screenCameraOverlayBusy = false
  screenCameraOverlayError = null
  screenShareWhileLiveBusy = false
  screenShareWhileLiveError = null
  if (room) {
    await releaseLocalTracks(room)
  }
  videoCleanup?.()
  videoCleanup = null
  audioCleanup?.()
  audioCleanup = null
  broadcasterRemoteSpeakerAudioCleanup?.()
  broadcasterRemoteSpeakerAudioCleanup = null
  conversationMicStateCleanup?.()
  conversationMicStateCleanup = null
  chatCleanup?.()
  chatCleanup = null
  handCleanup?.()
  handCleanup = null
  interactivePollOwners.delete("viewer-session")
  reconcileBroadcastInteractivePolling()
  if (viewerStatusRefreshTimer) {
    clearTimeout(viewerStatusRefreshTimer)
    viewerStatusRefreshTimer = null
  }
  localPreviewCleanup?.()
  localPreviewCleanup = null
  broadcasterPreviewElement = null
  broadcasterPreviewError = null
  cleanupBroadcastVideoAttachments()
  detachLocalBroadcastPreview()
  cleanupBroadcastRemoteAudio()
  if (room) {
    room.removeAllListeners()
    await room.disconnect()
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
  publisherCaptureDegraded = false
  broadcasterIdentityForRoom = null
  studioPresentation = "hidden"
  obsPublishRequestInFlight = false
  localHandRaised = false
  raisedHandIdentities = []
  handFeedback = null
  liveParticipants = []
  interactiveProfiles = {}
  streamListenMuted = false
  viewerMicMuted = false
  viewerMicPublishReady = false
  speakInviteNotice = null
  if (!preserveViewer) {
    viewerUserId = null
    viewerAccessToken = null
    dismissedSpeakInviteSessionId = null
  }
  speakerUpgradeInFlight = false
  speakerGrantUserIds = []
  sessionBlockUserIds = []
  boundViewerVideoElement = null
  speakerAutoUpgradeAttemptedSessionId = null
  setBroadcastStreamListenMuted(false)
  setBroadcastPublisherCredentials(null)
  intentionalBroadcastRoomTeardown = false
  } finally {
    await ensureScreenCaptureReleased()
  }
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
  const prev = status
  const merged: BroadcastRoomStatus = { ...next }
  if (
    merged.viewerCount === undefined &&
    prev.viewerCount !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.viewerCount = prev.viewerCount
  }
  const liteStatusPoll =
    isLiteBroadcastStatusPayload(merged) &&
    merged.broadcastSessionId === prev.broadcastSessionId

  if (
    merged.broadcasterConnected === undefined &&
    prev.broadcasterConnected !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId &&
    !liteStatusPoll
  ) {
    merged.broadcasterConnected = prev.broadcasterConnected
  }
  if (
    merged.broadcasterDisplayName === undefined &&
    prev.broadcasterDisplayName !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.broadcasterDisplayName = prev.broadcasterDisplayName
  }
  if (
    merged.broadcastSource === undefined &&
    prev.broadcastSource !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.broadcastSource = prev.broadcastSource
  }
  if (
    merged.videoSource === undefined &&
    prev.videoSource !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.videoSource = prev.videoSource
  }
  if (
    merged.primaryMediaPublisherIdentity === undefined &&
    prev.primaryMediaPublisherIdentity !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.primaryMediaPublisherIdentity = prev.primaryMediaPublisherIdentity
  }
  if (
    merged.livekitIngressId === undefined &&
    prev.livekitIngressId !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.livekitIngressId = prev.livekitIngressId
  }
  if (
    merged.ingressStatusSnapshot === undefined &&
    prev.ingressStatusSnapshot !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId
  ) {
    merged.ingressStatusSnapshot = prev.ingressStatusSnapshot
  }
  if (
    merged.hostConnected === undefined &&
    prev.hostConnected !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId &&
    !liteStatusPoll
  ) {
    merged.hostConnected = prev.hostConnected
  }
  if (
    merged.primaryMediaPublisherConnected === undefined &&
    prev.primaryMediaPublisherConnected !== undefined &&
    merged.live &&
    prev.live &&
    merged.broadcastSessionId === prev.broadcastSessionId &&
    !liteStatusPoll
  ) {
    merged.primaryMediaPublisherConnected = prev.primaryMediaPublisherConnected
  }
  if (
    merged.broadcastSessionId &&
    currentSessionId &&
    merged.broadcastSessionId !== currentSessionId
  ) {
    resetChatForNewSession(merged.broadcastSessionId)
    currentSessionId = merged.broadcastSessionId
  }
  if (
    merged.broadcastSessionId &&
    prev.broadcastSessionId &&
    merged.broadcastSessionId !== prev.broadcastSessionId
  ) {
    obsPublishRequestInFlight = false
  }
  if (merged.live === false) {
    obsPublishRequestInFlight = false
  }
  if (!merged.live && isWatching) {
    void teardownBroadcastRoom().then(() => emit())
  }
  if (
    merged.live &&
    merged.videoSource === "obs" &&
    merged.broadcastSessionId
  ) {
    merged.broadcastSource = "obs"
    if (!merged.primaryMediaPublisherIdentity?.trim()) {
      merged.primaryMediaPublisherIdentity =
        primaryMediaPublisherIdentityForBroadcastSession(merged.broadcastSessionId)
    }
  }
  if (merged.live) {
    const prevPl = prev.publicLive
    const prevVis = prev.visibility
    const resolved = resolveBroadcastLiveVisibility({
      mergedLive: true,
      mergedBroadcastSessionId: merged.broadcastSessionId,
      mergedVideoSource: merged.videoSource,
      mergedVisibility: merged.visibility,
      mergedPublicLive: merged.publicLive,
      prevLive: prev.live === true,
      prevBroadcastSessionId: prev.broadcastSessionId,
      prevVisibility: prev.visibility,
      prevPublicLive: prev.publicLive,
    })
    merged.visibility = resolved.visibility
    merged.publicLive = resolved.publicLive
    logBroadcast("setTradeRoomBroadcastStatus visibility", {
      sessionIdTail: merged.broadcastSessionId?.slice(-8) ?? null,
      videoSource: merged.videoSource ?? null,
      broadcastSource: merged.broadcastSource ?? null,
      prevPublicLive: prevPl ?? null,
      prevVisibility: prevVis ?? null,
      nextPublicLive: merged.publicLive ?? null,
      nextVisibility: merged.visibility ?? null,
    })
  }
  status = merged
  // DB `video_source` may be `obs`; viewer playback still uses screen vs camera on program publisher.
  if (merged.videoSource && merged.videoSource !== "obs") {
    preferredVideoSource = merged.videoSource
  }
  if (
    (merged.broadcastSource === "obs" || merged.videoSource === "obs") &&
    merged.primaryMediaPublisherIdentity?.trim()
  ) {
    activeBroadcastSource = "obs"
    activePrimaryMediaPublisherIdentity =
      merged.primaryMediaPublisherIdentity.trim()
  }
  emit()
}

export async function refreshTradeRoomBroadcastStatus(
  fetchStatus: () => Promise<BroadcastRoomStatus>
): Promise<void> {
  try {
    const prevSnap = { ...status }
    const next = await fetchStatus()
    logBroadcast("refreshTradeRoomBroadcastStatus before merge", {
      sessionIdTail: next.broadcastSessionId?.slice(-8) ?? null,
      live: next.live ?? null,
      publicLive: next.publicLive ?? null,
      visibility: next.visibility ?? null,
      videoSource: next.videoSource ?? null,
      prevPublicLive: prevSnap.publicLive ?? null,
      prevVisibility: prevSnap.visibility ?? null,
    })
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
  const normalized = {
    ...options,
    avatarUrl: normalizeBroadcastChatAvatarUrl(options.avatarUrl),
  }
  const result = await publishBroadcastChatMessage(broadcastRoom, normalized)
  if (result.ok) {
    const selfMsg = {
      id: `${options.userId}-${Date.now()}`,
      userId: options.userId,
      displayName: options.displayName,
      avatarUrl: normalized.avatarUrl,
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
    syncViewerMicPublishReady(broadcastRoom)
    emit()
  } catch (err) {
    error = err instanceof Error ? err.message : "Could not toggle microphone."
    emit()
  }
}

/** Re-attempt mic capture after a failed publish (e.g. permission denied). */
export async function retryTradeRoomBroadcastConversationMicrophone(): Promise<void> {
  if (!broadcastRoom || role !== "conversation") return
  try {
    await broadcastRoom.localParticipant.setMicrophoneEnabled(!viewerMicMuted)
    syncViewerMicPublishReady(broadcastRoom)
    if (!viewerMicMuted && !viewerMicPublishReady) {
      error =
        "Microphone is not publishing. Check browser permissions and try again."
    }
    emit()
  } catch (err) {
    viewerMicPublishReady = false
    error =
      err instanceof Error ? err.message : "Could not enable microphone."
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

/** Decline speaking invitation on the server and clear UI (revokes DB grant created at invite time). */
export async function declineTradeRoomBroadcastSpeakInvite(options: {
  accessToken: string
  invitationId: string
}): Promise<void> {
  await declineBroadcastSpeakInvite(
    options.accessToken.trim(),
    options.invitationId.trim()
  )
  dismissTradeRoomBroadcastSpeakInvite()
}

export async function acceptTradeRoomBroadcastSpeakInvite(options: {
  roomId: string
  videoElement: HTMLVideoElement
  accessToken: string
  /** Prefer when present: runs POST /api/livekit/broadcast/invite/respond (records accept, correct grantedBy). */
  invitationId?: string | null
  fetchConversationToken: () => Promise<{
    token: string
    livekitUrl: string
    broadcastSessionId: string
    broadcasterUserId: string
    broadcasterDisplayName: string | null
    startedAt: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
    broadcastSource?: BroadcastSource
    primaryMediaPublisherIdentity?: string | null
  }>
}): Promise<void> {
  if (speakerUpgradeInFlight || isBusy) return
  speakerUpgradeInFlight = true
  emit()
  try {
    const token = options.accessToken.trim()
    const inviteId = options.invitationId?.trim() ?? ""
    await joinTradeRoomBroadcastConversation({
      roomId: options.roomId,
      videoElement: options.videoElement,
      fetchJoin: () =>
        inviteId
          ? fetchBroadcastAcceptSpeakInvitePayload(token, inviteId)
          : options.fetchConversationToken(),
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

const OBS_CREDENTIALS_LOST_MESSAGE =
  "Streaming credentials exist for this session but are not available in this tab. Click Regenerate stream key to create new credentials."

/**
 * Create or refresh OBS RTMP credentials (host-only). Does not throw — sets `obsCredentialsError` on failure so the UI can stay in setup.
 * Single-flight per `sessionId`: concurrent callers share one HTTP sequence.
 * @param forceRecreate Revokes existing ingress on the server first (safe regenerate after refresh / lost memory).
 */
export async function ensureObsIngressCredentials(options: {
  roomId: string
  sessionId: string
  accessToken: string
  forceRecreate?: boolean
}): Promise<{ ok: true } | { ok: false; message: string }> {
  const sessionKey = options.sessionId.trim()
  const token = options.accessToken.trim()

  return runSingleFlightByKey(
    obsCredentialsFlightBySession,
    sessionKey,
    options.forceRecreate === true,
    async (): Promise<{ ok: true } | { ok: false; message: string }> => {
      logBroadcast("ensureObsIngressCredentials enter", {
        sessionIdTail: sessionKey.slice(-8),
        forceRecreate: options.forceRecreate === true,
      })
      if (
        obsHasIngressCredentials &&
        obsRtmpUrlMemory?.trim() &&
        obsStreamKeyMemory?.trim() &&
        !options.forceRecreate
      ) {
        logBroadcast("ensureObsIngressCredentials skip (already in memory)", {
          sessionIdTail: sessionKey.slice(-8),
        })
        return { ok: true }
      }

      obsCredentialsBusy = true
      obsCredentialsError = null
      obsCredentialsLostOrUnavailable = false
      emit()

      try {
        if (options.forceRecreate) {
          obsHasIngressCredentials = false
          obsCredentialsLostOrUnavailable = false
          obsRtmpUrlMemory = null
          obsStreamKeyMemory = null
          obsStreamKeyRevealed = false
          const rev = await fetch("/api/livekit/broadcast/obs/revoke", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({
              roomId: options.roomId,
              sessionId: options.sessionId,
            }),
          })
          if (!rev.ok) {
            const revPayload = (await rev.json().catch(() => ({}))) as {
              error?: string
            }
            const msg =
              revPayload.error || "Could not revoke previous OBS credentials."
            obsHasIngressCredentials = false
            obsCredentialsError = msg
            emit()
            return { ok: false, message: msg }
          }
        }

        const statusSessionMatches =
          status.broadcastSessionId === sessionKey ||
          currentSessionId === sessionKey
        const existingIngressId =
          statusSessionMatches &&
          (status.live === true || (isPublishing && currentSessionId === sessionKey))
            ? status.livekitIngressId?.trim() ?? ""
            : ""
        // Infer OBS mode even if lite status omitted broadcastSource (session is OBS).
        const inferredObs =
          status.videoSource === "obs" ||
          status.broadcastSource === "obs" ||
          activeBroadcastSource === "obs" ||
          resolveEffectiveBroadcastMode() === "obs"

        const duplicateWould409 =
          !options.forceRecreate &&
          existingIngressId.length > 0 &&
          inferredObs

        if (duplicateWould409) {
          obsHasIngressCredentials = false
          obsRtmpUrlMemory = null
          obsStreamKeyMemory = null
          obsStreamKeyRevealed = false
          obsCredentialsLostOrUnavailable = true
          obsCredentialsError = OBS_CREDENTIALS_LOST_MESSAGE
          emit()
          return { ok: false, message: OBS_CREDENTIALS_LOST_MESSAGE }
        }

        const res = await fetch("/api/livekit/broadcast/obs/credentials", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            roomId: options.roomId,
            sessionId: options.sessionId,
          }),
        })
        const payload = (await res.json().catch(() => ({}))) as {
          error?: string
          rtmpUrl?: string
          streamKey?: string
          primaryMediaPublisherIdentity?: string
          livekitIngressId?: string
          ingressStatusSnapshot?: string
        }
        if (!res.ok) {
          if (res.status === 409 && !options.forceRecreate) {
            obsHasIngressCredentials = false
            obsRtmpUrlMemory = null
            obsStreamKeyMemory = null
            obsStreamKeyRevealed = false
            obsCredentialsLostOrUnavailable = true
            obsCredentialsError = OBS_CREDENTIALS_LOST_MESSAGE
            status = {
              ...status,
              broadcastSource: "obs",
            }
            emit()
            return { ok: false, message: OBS_CREDENTIALS_LOST_MESSAGE }
          }
          const msg =
            payload.error || "Could not create OBS streaming credentials."
          obsHasIngressCredentials = false
          obsRtmpUrlMemory = null
          obsStreamKeyMemory = null
          obsCredentialsLostOrUnavailable = false
          obsCredentialsError = msg
          emit()
          return { ok: false, message: msg }
        }
        const rtmpUrl = payload.rtmpUrl?.trim() || ""
        const streamKey = payload.streamKey?.trim() || ""
        if (!rtmpUrl || !streamKey) {
          const msg =
            "Server returned an invalid OBS credential response (missing RTMP URL or stream key)."
          obsHasIngressCredentials = false
          obsCredentialsLostOrUnavailable = false
          obsCredentialsError = msg
          emit()
          return { ok: false, message: msg }
        }
        obsRtmpUrlMemory = rtmpUrl
        obsStreamKeyMemory = streamKey
        obsHasIngressCredentials = true
        obsCredentialsLostOrUnavailable = false
        obsCredentialsError = null
        const primaryId =
          payload.primaryMediaPublisherIdentity?.trim() ||
          primaryMediaPublisherIdentityForBroadcastSession(options.sessionId)
        activePrimaryMediaPublisherIdentity = primaryId
        status = {
          ...status,
          broadcastSource: "obs",
          primaryMediaPublisherIdentity:
            primaryId ||
            status.primaryMediaPublisherIdentity ||
            activePrimaryMediaPublisherIdentity,
          livekitIngressId: payload.livekitIngressId ?? status.livekitIngressId,
          ingressStatusSnapshot:
            payload.ingressStatusSnapshot ?? status.ingressStatusSnapshot,
        }
        activeBroadcastSource = "obs"
        activePrimaryMediaPublisherIdentity = primaryId
        emit()
        return { ok: true }
      } catch (err) {
        const msg =
          err instanceof Error
            ? err.message
            : "Could not create OBS streaming credentials."
        obsHasIngressCredentials = false
        obsRtmpUrlMemory = null
        obsStreamKeyMemory = null
        obsCredentialsLostOrUnavailable = false
        obsCredentialsError = msg
        emit()
        return { ok: false, message: msg }
      } finally {
        obsCredentialsBusy = false
        emit()
      }
    }
  )
}

export function setObsStreamKeyRevealed(revealed: boolean): void {
  obsStreamKeyRevealed = revealed
  emit()
}

export async function copyObsFieldToClipboard(value: string): Promise<void> {
  const v = value.trim()
  if (!v || typeof navigator === "undefined" || !navigator.clipboard?.writeText) {
    return
  }
  await navigator.clipboard.writeText(v)
}

/**
 * OBS Stage 2: make the preparing session public (notifications once, viewer tokens enabled).
 */
export async function publishTradeRoomBroadcastObs(options: {
  roomId: string
  accessToken: string
}): Promise<void> {
  if (!roomId || !options.accessToken.trim()) return
  obsPublishRequestInFlight = true
  emit()
  try {
    const res = await fetch("/api/livekit/broadcast/publish", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken.trim()}`,
      },
      body: JSON.stringify({ roomId: options.roomId }),
    })
    const payload = (await res.json().catch(() => ({}))) as {
      error?: string
      ok?: boolean
      alreadyPublic?: boolean
    }
    if (!res.ok) {
      throw new Error(payload.error || "Could not go live.")
    }
    setTradeRoomBroadcastStatus({
      ...status,
      live: true,
      publicLive: true,
      visibility: "public",
    })
    studioPresentation = "studio"
    error = null

    if (
      obsDeferredEnableHostMic &&
      broadcastRoom &&
      role === "broadcaster" &&
      (status.videoSource === "obs" || activeBroadcastSource === "obs")
    ) {
      try {
        await broadcastRoom.localParticipant.setMicrophoneEnabled(true)
        broadcasterMicMuted = false
        broadcasterMicWarning = null
        try {
          await broadcastRoom.localParticipant.setCameraEnabled(false)
          await broadcastRoom.localParticipant.setScreenShareEnabled(false)
        } catch {
          // Keep program video OBS-only after mic enable.
        }
      } catch (micErr) {
        broadcasterMicWarning =
          "Microphone unavailable for moderation and voice features. Check browser permissions."
        console.warn("[broadcast] obs host mic publish failed after go live", micErr)
      }
      obsDeferredEnableHostMic = false
    }

    emit()
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : "Could not go live for viewers."
    error = msg
    emit()
    throw err
  } finally {
    obsPublishRequestInFlight = false
    emit()
  }
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
    broadcastSource?: BroadcastSource
    primaryMediaPublisherIdentity?: string | null
  }>
  fetchStop: (sessionId: string) => Promise<void>
}): Promise<void> {
  if (isBusy) return
  isBusy = true
  error = null
  obsBroadcastBootstrapping = options.setup.videoSource === "obs"
  obsPublishRequestInFlight = false
  emit()

  logBroadcast("startTradeRoomBroadcast enter", {
    roomId: options.roomId,
    videoSource: options.setup.videoSource,
    obsBootstrap: obsBroadcastBootstrapping,
  })

  try {
    if (broadcastRoom && roomId !== options.roomId) {
      await stopTradeRoomBroadcast({
        roomId: roomId ?? options.roomId,
        sessionId: currentSessionId ?? "",
        fetchStop: async () => {},
        skipApi: true,
      })
    }

    const voice = getTradeRoomLiveVoiceSnapshot()
    if (
      voice.session?.roomId === options.roomId &&
      (voice.connectionState === ConnectionState.Connected ||
        voice.connectionState === ConnectionState.Reconnecting)
    ) {
      await leaveTradeRoomLiveVoice()
    }
    generalVoiceOverlapWarning = generalVoiceWarningIfNeeded()

    const start = await options.fetchStart()
    const isObsSession = start.videoSource === "obs"
    const startPublicLive =
      (start as { publicLive?: boolean }).publicLive ??
      (!isObsSession ? true : false)
    const startVisibility = (start as { visibility?: "public" | "preparing" })
      .visibility ?? (isObsSession ? "preparing" : "public")
    const resolvedPrimaryMediaIdentity = isObsSession
      ? start.primaryMediaPublisherIdentity?.trim() ||
        primaryMediaPublisherIdentityForBroadcastSession(start.broadcastSessionId)
      : start.primaryMediaPublisherIdentity?.trim() ?? null
    roomId = options.roomId
    resetChatForNewSession(start.broadcastSessionId)
    currentSessionId = start.broadcastSessionId
    broadcasterIdentityForRoom = start.broadcasterUserId
    preferredVideoSource = start.videoSource
    activeBroadcastSource = isObsSession ? "obs" : "browser"
    activePrimaryMediaPublisherIdentity = resolvedPrimaryMediaIdentity
    role = "broadcaster"
    isPublishing = true
    isWatching = false
    isInConversation = false
    broadcasterMicMuted = false
    broadcasterMicWarning = null
    resetObsCredentialMemory()
    obsDeferredEnableHostMic =
      isObsSession && options.setup.enableBroadcasterMic === true

    status = {
      live: true,
      publicLive: startPublicLive,
      visibility: startVisibility,
      broadcastSessionId: start.broadcastSessionId,
      broadcasterUserId: start.broadcasterUserId,
      broadcasterDisplayName: start.broadcasterDisplayName,
      startedAt: start.startedAt,
      voiceMode: start.voiceMode,
      videoSource: start.videoSource,
      broadcastSource:
        start.broadcastSource ?? (isObsSession ? "obs" : "browser"),
      primaryMediaPublisherIdentity: resolvedPrimaryMediaIdentity,
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
      videoSource: start.videoSource,
      publicLive: status.publicLive ?? null,
      visibility: status.visibility ?? null,
    })

    if (isObsSession) {
      try {
        await nextRoom.localParticipant.setCameraEnabled(false)
        await nextRoom.localParticipant.setScreenShareEnabled(false)
      } catch {
        // Best-effort: ensure host browser is not publishing a second video track beside OBS ingress.
      }
    }

    nextRoom.on(RoomEvent.LocalTrackPublished, () => {
      syncAudienceCount(nextRoom, start.broadcasterUserId)
      emit()
    })

    attachRoomSync(nextRoom, start.broadcasterUserId)
    registerChat(nextRoom)
    registerHand(nextRoom)
    const isWebcamGoLive = !isObsSession && start.videoSource === "camera"
    if (!isObsSession && !isWebcamGoLive) {
      studioPresentation = "studio"
    }

    if (isObsSession) {
      broadcasterPreviewError = null
      localPreviewCleanup?.()
      localPreviewCleanup = null

      if (options.publisherAccessToken) {
        await ensureObsIngressCredentials({
          roomId: options.roomId,
          sessionId: start.broadcastSessionId,
          accessToken: options.publisherAccessToken,
        })
      }

      status = {
        ...status,
        broadcastSource: "obs",
        primaryMediaPublisherIdentity:
          activePrimaryMediaPublisherIdentity ||
          status.primaryMediaPublisherIdentity ||
          null,
      }

      videoCleanup?.()
      audioCleanup?.()
      videoCleanup = registerBroadcastVideoHandlers(nextRoom, {
        broadcastSource: "obs",
        primaryMediaPublisherIdentity: activePrimaryMediaPublisherIdentity,
        broadcasterUserId: start.broadcasterUserId,
        preferredSource: "screen",
        getVideoElement: () => broadcasterPreviewElement,
      })
      registerBroadcasterRemoteSpeakerAudio(nextRoom, start.broadcasterUserId)
    } else {
      registerBroadcasterRemoteSpeakerAudio(nextRoom, start.broadcasterUserId)

      if (!isWebcamGoLive) {
        localPreviewCleanup?.()
        localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
          nextRoom,
          () => broadcasterPreviewElement,
          start.videoSource
        )
      }

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
        const captureFailedAt = "browser getUserMedia (before LiveKit publish)"
        logBroadcast("broadcaster video publish failed", {
          roomId: options.roomId,
          videoSource: start.videoSource,
          errorName:
            videoErr instanceof Error ? videoErr.name : typeof videoErr,
          message:
            videoErr instanceof Error ? videoErr.message : String(videoErr),
          captureFailedAt,
        })
        const userMessage = broadcastStartErrorMessage(videoErr)
        error = userMessage
        broadcasterPreviewError = userMessage
        studioPresentation = "hidden"
        emit()
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
          videoSource: start.videoSource,
        })
        error = reason
        broadcasterPreviewError = reason
        studioPresentation = "hidden"
        emit()
        await options.fetchStop(start.broadcastSessionId).catch(() => {})
        await teardownBroadcastRoom()
        throw new Error(reason)
      }

      if (isWebcamGoLive) {
        localPreviewCleanup?.()
        localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
          nextRoom,
          () => broadcasterPreviewElement,
          start.videoSource
        )
        studioPresentation = "studio"
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
        publisherCaptureDegraded = true
        const endedMsg =
          start.videoSource === "screen"
            ? "Screen sharing stopped. Choose Retry to share again, or End stream."
            : "Camera stopped. Choose Retry or End stream."
        broadcasterPreviewError = endedMsg
        error = null
        if (studioPresentation === "hidden") {
          studioPresentation = "mini"
        }
        emit()
      })
    }

    if (options.publisherAccessToken) {
      setBroadcastPublisherCredentials({
        roomId: options.roomId,
        sessionId: start.broadcastSessionId,
        accessToken: options.publisherAccessToken,
        endSessionOnUnload: !isObsSession,
      })
    }

    connectionState = nextRoom.state
    emit()
  } catch (err) {
    if (options.setup.videoSource === "obs") {
      const msg = broadcastStartErrorMessage(err)
      error = msg
      if (broadcastRoom) {
        await broadcastRoom.disconnect().catch(() => {})
        broadcastRoom = null
      }
      videoCleanup?.()
      videoCleanup = null
      audioCleanup?.()
      audioCleanup = null
      broadcasterRemoteSpeakerAudioCleanup?.()
      broadcasterRemoteSpeakerAudioCleanup = null
      chatCleanup?.()
      chatCleanup = null
      handCleanup?.()
      handCleanup = null
      connectionState = ConnectionState.Disconnected
      role = "none"
      isPublishing = false
      isWatching = false
      isInConversation = false
      clearObsStudioMemory()
      obsDeferredEnableHostMic = false
    } else {
      error = broadcastStartErrorMessage(err)
      await teardownBroadcastRoom()
      roomId = null
    }
    emit()
  } finally {
    isBusy = false
    obsBroadcastBootstrapping = false
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
    broadcastSource?: BroadcastSource
    primaryMediaPublisherIdentity?: string | null
    publicLive?: boolean
    visibility?: "public" | "preparing"
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
  activeBroadcastSource =
    tokenPayload.broadcastSource ??
    (tokenPayload.videoSource === "obs" ? "obs" : "browser")
  activePrimaryMediaPublisherIdentity =
    tokenPayload.primaryMediaPublisherIdentity?.trim() || null
  role = options.asConversation ? "conversation" : "viewer"
  isInConversation = options.asConversation
  isWatching = true
  isPublishing = false
  generalVoiceOverlapWarning = generalVoiceWarningIfNeeded()

  const pub =
    tokenPayload.publicLive === true ||
    tokenPayload.visibility === "public"
  status = {
    live: true,
    publicLive: pub,
    visibility: tokenPayload.visibility ?? (pub ? "public" : "preparing"),
    broadcastSessionId: tokenPayload.broadcastSessionId,
    broadcasterUserId: tokenPayload.broadcasterUserId,
    broadcasterDisplayName: tokenPayload.broadcasterDisplayName,
    startedAt: tokenPayload.startedAt,
    voiceMode: tokenPayload.voiceMode,
    videoSource: tokenPayload.videoSource,
    broadcastSource: activeBroadcastSource,
    primaryMediaPublisherIdentity: activePrimaryMediaPublisherIdentity,
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
  if (options.asConversation) {
    registerConversationMicPublishListeners(nextRoom)
  } else {
    viewerMicPublishReady = false
  }
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
      syncViewerMicPublishReady(nextRoom)
    } catch (err) {
      error =
        err instanceof Error ? err.message : "Could not enable microphone."
      viewerMicMuted = true
      viewerMicPublishReady = false
    }
  }

  if (viewerAccessToken) {
    setBroadcastInteractivePollDemand("viewer-session", true, viewerAccessToken)
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
    broadcastSource?: BroadcastSource
    primaryMediaPublisherIdentity?: string | null
  }>
}): Promise<void> {
  if (isBusy) return
  viewerBroadcastConnectionLost = null
  if (
    isWatching &&
    !isInConversation &&
    roomId === options.roomId &&
    broadcastRoom?.state === ConnectionState.Connected &&
    currentSessionId != null &&
    broadcasterIdentityForRoom
  ) {
    boundViewerVideoElement = options.videoElement
    reattachBroadcastVideoToElement(broadcastRoom!, {
      broadcastSource: status.broadcastSource ?? "browser",
      primaryMediaPublisherIdentity: status.primaryMediaPublisherIdentity,
      broadcasterUserId: broadcasterIdentityForRoom,
      videoEl: options.videoElement,
      preferredSource:
        preferredVideoSource === "obs" ? "screen" : preferredVideoSource,
    })
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
    if (err instanceof BroadcastNoActiveStreamError) {
      await teardownBroadcastRoom({ preserveViewerCredentials: true })
      isWatching = false
      error = null
      roomId = options.roomId
      emit()
      return
    }
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
    broadcastSource?: BroadcastSource
    primaryMediaPublisherIdentity?: string | null
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
      broadcastSource?: BroadcastSource
      primaryMediaPublisherIdentity?: string | null
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
        broadcastSource: viewer.broadcastSource,
        primaryMediaPublisherIdentity: viewer.primaryMediaPublisherIdentity,
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

async function fetchBroadcastStopApi(
  activeRoomId: string,
  sessionId: string,
  fetchStop?: () => Promise<void>
): Promise<void> {
  if (fetchStop) {
    await fetchStop()
    return
  }
  const creds = getBroadcastPublisherCredentials()
  const token = creds?.accessToken?.trim() ?? ""
  if (!token) {
    throw new Error("Sign in to end the stream.")
  }
  const res = await fetch("/api/livekit/broadcast/stop", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ roomId: activeRoomId, sessionId }),
  })
  if (!res.ok) {
    const payload = (await res.json().catch(() => ({}))) as { error?: string }
    throw new Error(payload.error || "Could not stop the stream on the server.")
  }
}

export async function stopTradeRoomBroadcast(options: {
  roomId: string
  sessionId: string
  fetchStop?: () => Promise<void>
  skipApi?: boolean
}): Promise<void> {
  isBusy = true
  emit()

  const creds = getBroadcastPublisherCredentials()
  const sessionId =
    options.sessionId?.trim() ||
    currentSessionId?.trim() ||
    creds?.sessionId?.trim() ||
    ""
  const activeRoomId =
    options.roomId?.trim() || roomId?.trim() || creds?.roomId?.trim() || ""

  let apiError: string | null = null
  try {
    if (!options.skipApi && sessionId && activeRoomId) {
      try {
        await fetchBroadcastStopApi(activeRoomId, sessionId, options.fetchStop)
      } catch (err) {
        apiError =
          err instanceof Error ? err.message : "Could not stop the stream."
        try {
          await fetchBroadcastStopApi(activeRoomId, sessionId)
        } catch (retryErr) {
          apiError =
            retryErr instanceof Error
              ? retryErr.message
              : apiError
        }
      }
    }
  } finally {
    await teardownBroadcastRoom()
    status = { live: false }
    roomId = null
    isBusy = false
    obsBroadcastBootstrapping = false
    error = apiError
    emit()
  }
}

/** Re-publish screen or camera after user stopped sharing or capture failed. */
export async function retryTradeRoomBroadcasterCapture(): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (activeBroadcastSource === "obs" || status.videoSource === "obs") return
  const source = preferredVideoSource === "camera" ? "camera" : "screen"
  isBusy = true
  error = null
  emit()
  try {
    if (source === "camera") {
      await broadcastRoom.localParticipant.setCameraEnabled(true, {
        resolution: { width: 1280, height: 720, frameRate: 24 },
      })
    } else {
      await broadcastRoom.localParticipant.setScreenShareEnabled(true, {
        audio: false,
        selfBrowserSurface: "include",
        surfaceSwitching: "include",
      })
    }
    const localPub = findLocalBroadcastVideoPublication(broadcastRoom, source)
    if (!localPub?.track) {
      throw new Error(
        source === "screen"
          ? "Screen share was not started."
          : "Camera track was not published."
      )
    }
    localPreviewCleanup?.()
    localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
      broadcastRoom,
      () => broadcasterPreviewElement,
      source
    )
    localPub.track.mediaStreamTrack.addEventListener("ended", () => {
      if (source === "screen") {
        if (getScreenOverlaySessionActive() || source === "screen") {
          void releaseBrowserScreenShareCapture(broadcastRoom, {
            stopDisplayCapture: true,
          })
        }
        publisherCaptureDegraded = true
        broadcasterPreviewError =
          "Screen sharing stopped. Use Change share, Retry, or End stream."
      } else {
        publisherCaptureDegraded = true
        broadcasterPreviewError =
          "Camera stopped. Choose Retry or End stream."
      }
      error = null
      if (studioPresentation === "hidden") {
        studioPresentation = "mini"
      }
      emit()
    })
    if (source === "screen" && screenCameraOverlayEnabled) {
      if (!getScreenOverlaySessionActive()) {
        await enableScreenCameraOverlay(
          broadcastRoom,
          screenCameraOverlayPosition
        )
        try {
          await broadcastRoom.localParticipant.setCameraEnabled(false)
        } catch {
          // ignore
        }
        screenCameraOverlayCameraVisible = true
      }
      const rawScreen = getScreenOverlayRawScreenTrack()
      if (rawScreen) bindBroadcasterScreenShareEnded(rawScreen)
      resyncBroadcasterPreviewAfterProgramChange()
    }
    if (broadcasterPreviewElement) {
      const preview = syncLocalBroadcastPreviewToElement(
        broadcastRoom,
        broadcasterPreviewElement,
        source
      )
      broadcasterPreviewError = preview.ok ? null : preview.reason
    } else {
      broadcasterPreviewError = null
    }
    publisherCaptureDegraded = false
    connectionState = broadcastRoom.state
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : "Could not restart capture."
    broadcasterPreviewError = msg
    error = msg
    publisherCaptureDegraded = true
  } finally {
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
  reattachBroadcastVideoToElement(broadcastRoom, {
    broadcastSource: status.broadcastSource ?? "browser",
    primaryMediaPublisherIdentity: status.primaryMediaPublisherIdentity,
    broadcasterUserId: broadcasterIdentityForRoom,
    videoEl: videoElement,
    preferredSource:
      preferredVideoSource === "obs" ? "screen" : preferredVideoSource,
  })
}

/** Broadcaster local preview — uses published local track, not remote subscription. */
export function syncTradeRoomBroadcastLocalPreviewElement(
  videoElement: HTMLVideoElement
): void {
  const prevPreviewEl = broadcasterPreviewElement
  broadcasterPreviewElement = videoElement
  if (!broadcastRoom || role !== "broadcaster" || !isPublishing) return
  if ((status.broadcastSource ?? activeBroadcastSource) === "obs") {
    const programId =
      (status.primaryMediaPublisherIdentity ?? activePrimaryMediaPublisherIdentity)?.trim() ??
      ""
    if (
      prevPreviewEl &&
      prevPreviewEl !== videoElement &&
      programId &&
      isObsIngressPublisherIdentity(programId)
    ) {
      detachObsIngressVideoTracksFromElement(
        broadcastRoom,
        programId,
        prevPreviewEl
      )
    }
    broadcasterPreviewError = null
    reattachBroadcastVideoToElement(broadcastRoom, {
      broadcastSource: "obs",
      primaryMediaPublisherIdentity:
        status.primaryMediaPublisherIdentity ?? activePrimaryMediaPublisherIdentity,
      broadcasterUserId: broadcasterIdentityForRoom ?? status.broadcasterUserId ?? "",
      videoEl: videoElement,
      preferredSource: "screen",
    })
    emit()
    return
  }
  const preview = syncLocalBroadcastPreviewToElement(
    broadcastRoom,
    videoElement,
    activeBroadcastSource === "obs" ? "screen" : undefined
  )
  broadcasterPreviewError = preview.ok ? null : preview.reason
  emit()
}

export function getTradeRoomBroadcastLocalPreviewError(): string | null {
  return broadcasterPreviewError
}

function resyncBroadcasterPreviewAfterProgramChange(): void {
  if (!broadcastRoom || !broadcasterPreviewElement || !isPublishing) return
  const preview = syncLocalBroadcastPreviewToElement(
    broadcastRoom,
    broadcasterPreviewElement
  )
  broadcasterPreviewError = preview.ok ? null : preview.reason
}

function bindBroadcasterScreenShareEnded(rawScreen: MediaStreamTrack): void {
  rawScreen.addEventListener(
    "ended",
    () => {
      if (getScreenOverlaySessionActive() || preferredVideoSource === "screen") {
        void releaseBrowserScreenShareCapture(broadcastRoom, {
          stopDisplayCapture: true,
        })
      }
      publisherCaptureDegraded = true
      broadcasterPreviewError =
        "Screen sharing stopped. Use Change share, Retry, or End stream."
      error = null
      if (studioPresentation === "hidden") {
        studioPresentation = "mini"
      }
      emit()
    },
    { once: true }
  )
}

async function publishBrowserScreenShareWithOverlay(room: Room): Promise<void> {
  await room.localParticipant.setScreenShareEnabled(
    true,
    BROWSER_SCREEN_SHARE_OPTS
  )
  const screenPub = findLocalBroadcastVideoPublication(room, "screen")
  if (!screenPub?.track) {
    throw new Error("Screen share was cancelled or no video track was published.")
  }
  await enableScreenCameraOverlay(room, screenCameraOverlayPosition)
  try {
    await room.localParticipant.setCameraEnabled(false)
  } catch (err) {
    logBroadcast("unpublish camera after screen program", {
      message: err instanceof Error ? err.message : String(err),
    })
  }
  const rawScreen = getScreenOverlayRawScreenTrack()
  if (rawScreen) {
    bindBroadcasterScreenShareEnded(rawScreen)
  }
  preferredVideoSource = "screen"
  status = { ...status, videoSource: "screen" }
  screenCameraOverlayEnabled = true
  screenCameraOverlayCameraVisible = true
  publisherCaptureDegraded = false
  broadcasterPreviewError = null
  screenShareWhileLiveError = null
  localPreviewCleanup?.()
  localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
    room,
    () => broadcasterPreviewElement
  )
  studioPresentation = "studio"
  resyncBroadcasterPreviewAfterProgramChange()
  logBroadcast("browser program switched to screen share", {
    screenTrackSid: screenPub.trackSid ?? screenPub.track?.sid ?? null,
    cameraStillPublished: Boolean(
      findLocalBroadcastVideoPublication(room, "camera")?.track
    ),
  })
}

async function promptBrowserScreenShareWithOverlay(room: Room): Promise<void> {
  try {
    await publishBrowserScreenShareWithOverlay(room)
  } catch (err) {
    if (isBroadcastScreenShareCancelled(err)) {
      await room.localParticipant.setScreenShareEnabled(false).catch(() => {})
      return
    }
    await room.localParticipant.setScreenShareEnabled(false).catch(() => {})
    throw err
  }
}

function switchBroadcasterPreviewToCamera(room: Room): void {
  preferredVideoSource = "camera"
  status = { ...status, videoSource: "camera" }
  screenCameraOverlayEnabled = false
  screenCameraOverlayCameraVisible = false
  publisherCaptureDegraded = false
  broadcasterPreviewError = null
  screenShareWhileLiveError = null
  localPreviewCleanup?.()
  localPreviewCleanup = registerLocalBroadcastPreviewHandlers(
    room,
    () => broadcasterPreviewElement
  )
  resyncBroadcasterPreviewAfterProgramChange()
  logBroadcast("browser program switched to camera", {
    cameraTrackSid:
      findLocalBroadcastVideoPublication(room, "camera")?.trackSid ?? null,
  })
}

export async function startTradeRoomBroadcastScreenShareWhileLive(): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (activeBroadcastSource === "obs" || status.videoSource === "obs") return
  if (status.videoSource === "screen") return
  if (status.videoSource !== "camera") return
  if (screenShareWhileLiveBusy || screenCameraOverlayBusy) return

  screenShareWhileLiveBusy = true
  screenShareWhileLiveError = null
  emit()
  try {
    await promptBrowserScreenShareWithOverlay(broadcastRoom)
  } catch (err) {
    if (!isBroadcastScreenShareCancelled(err)) {
      screenShareWhileLiveError =
        err instanceof Error ? err.message : "Could not start screen sharing."
      logBroadcast("screen share while live failed", {
        message: screenShareWhileLiveError,
        errorName: err instanceof Error ? err.name : typeof err,
      })
    }
  } finally {
    screenShareWhileLiveBusy = false
    emit()
  }
}

export async function switchTradeRoomBroadcastScreenShareSurface(): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (activeBroadcastSource === "obs" || status.videoSource === "obs") return
  if (status.videoSource !== "screen" && preferredVideoSource !== "screen") {
    return
  }
  if (screenShareWhileLiveBusy || screenCameraOverlayBusy) return

  const hadOverlay = getScreenOverlaySessionActive()
  screenShareWhileLiveBusy = true
  screenShareWhileLiveError = null
  emit()
  try {
    if (hadOverlay) {
      await disableScreenCameraOverlay(broadcastRoom)
      screenCameraOverlayEnabled = false
      screenCameraOverlayCameraVisible = false
    }
    try {
      await broadcastRoom.localParticipant.setScreenShareEnabled(
        true,
        BROWSER_SCREEN_SHARE_OPTS
      )
    } catch (err) {
      if (isBroadcastScreenShareCancelled(err)) return
      throw err
    }
    const screenPub = findLocalBroadcastVideoPublication(broadcastRoom, "screen")
    if (!screenPub?.track) {
      throw new Error("Screen share was cancelled or no video track was published.")
    }
    if (hadOverlay || screenCameraOverlayEnabled) {
      await enableScreenCameraOverlay(
        broadcastRoom,
        screenCameraOverlayPosition
      )
      try {
        await broadcastRoom.localParticipant.setCameraEnabled(false)
      } catch {
        // ignore
      }
      screenCameraOverlayEnabled = true
      screenCameraOverlayCameraVisible = true
      const rawScreen = getScreenOverlayRawScreenTrack()
      if (rawScreen) bindBroadcasterScreenShareEnded(rawScreen)
    }
    resyncBroadcasterPreviewAfterProgramChange()
    publisherCaptureDegraded = false
    broadcasterPreviewError = null
  } catch (err) {
    if (!isBroadcastScreenShareCancelled(err)) {
      screenShareWhileLiveError =
        err instanceof Error
          ? err.message
          : "Could not change the shared screen."
    }
  } finally {
    screenShareWhileLiveBusy = false
    emit()
  }
}

export async function stopTradeRoomBroadcastScreenShareWhileLive(): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (activeBroadcastSource === "obs" || status.videoSource === "obs") return
  if (status.videoSource !== "screen" && preferredVideoSource !== "screen") {
    return
  }
  if (screenShareWhileLiveBusy || screenCameraOverlayBusy) return

  screenShareWhileLiveBusy = true
  screenShareWhileLiveError = null
  emit()
  try {
    await releaseBrowserScreenShareCapture(broadcastRoom, {
      stopDisplayCapture: true,
    })
    try {
      await broadcastRoom.localParticipant.setCameraEnabled(false)
    } catch {
      // ignore stale unpublish
    }
    await broadcastRoom.localParticipant.setCameraEnabled(true, {
      resolution: { width: 1280, height: 720, frameRate: 24 },
    })
    const cameraPub = findLocalBroadcastVideoPublication(broadcastRoom, "camera")
    if (!cameraPub?.track) {
      throw new Error("Camera track was not available after stopping screen share.")
    }
    cameraPub.track.mediaStreamTrack.addEventListener(
      "ended",
      () => {
        publisherCaptureDegraded = true
        broadcasterPreviewError =
          "Camera stopped. Choose Retry or End stream."
        if (studioPresentation === "hidden") {
          studioPresentation = "mini"
        }
        emit()
      },
      { once: true }
    )
    switchBroadcasterPreviewToCamera(broadcastRoom)
  } catch (err) {
    screenShareWhileLiveError =
      err instanceof Error
        ? err.message
        : "Could not stop screen sharing."
    logBroadcast("stop screen share while live failed", {
      message: screenShareWhileLiveError,
    })
  } finally {
    if (broadcastRoom) {
      await releaseBrowserScreenShareCapture(broadcastRoom, {
        stopDisplayCapture: true,
      }).catch(() => {})
    }
    screenShareWhileLiveBusy = false
    emit()
  }
}

export function tradeRoomBroadcastScreenOverlayAvailable(
  snapshot: Pick<
    BroadcastStoreSnapshot,
    "isPublishing" | "role" | "status"
  >
): boolean {
  if (!snapshot.isPublishing || snapshot.role !== "broadcaster") return false
  if (snapshot.status.videoSource !== "screen") return false
  if (snapshot.status.broadcastSource === "obs") return false
  return true
}

export async function setTradeRoomBroadcastScreenCameraOverlayEnabled(
  enabled: boolean
): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (status.videoSource !== "screen") return
  if (screenCameraOverlayBusy) return
  screenCameraOverlayBusy = true
  screenCameraOverlayError = null
  emit()
  try {
    if (enabled) {
      await enableScreenCameraOverlay(
        broadcastRoom,
        screenCameraOverlayPosition
      )
      screenCameraOverlayEnabled = true
      screenCameraOverlayCameraVisible = true
    } else {
      await disableScreenCameraOverlay(broadcastRoom)
      screenCameraOverlayEnabled = false
      screenCameraOverlayCameraVisible = false
    }
    resyncBroadcasterPreviewAfterProgramChange()
  } catch (err) {
    screenCameraOverlayError =
      err instanceof Error
        ? err.message
        : "Could not update the camera overlay."
    screenCameraOverlayEnabled = getScreenOverlaySessionActive()
    logBroadcast("screen overlay toggle failed", {
      enabled,
      message: screenCameraOverlayError,
      errorName: err instanceof Error ? err.name : typeof err,
    })
  } finally {
    screenCameraOverlayBusy = false
    emit()
  }
}

export async function setTradeRoomBroadcastScreenOverlayCameraVisible(
  visible: boolean
): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  if (!screenCameraOverlayEnabled && !visible) return
  if (screenCameraOverlayBusy) return
  screenCameraOverlayBusy = true
  screenCameraOverlayError = null
  emit()
  try {
    if (!screenCameraOverlayEnabled && visible) {
      await enableScreenCameraOverlay(
        broadcastRoom,
        screenCameraOverlayPosition
      )
      screenCameraOverlayEnabled = true
    }
    await setScreenOverlayCameraVisible(broadcastRoom, visible)
    screenCameraOverlayCameraVisible = visible
    screenCameraOverlayEnabled = getScreenOverlaySessionActive()
    resyncBroadcasterPreviewAfterProgramChange()
  } catch (err) {
    screenCameraOverlayError =
      err instanceof Error ? err.message : "Could not change overlay camera."
  } finally {
    screenCameraOverlayBusy = false
    emit()
  }
}

export async function setTradeRoomBroadcastScreenCameraOverlayPosition(
  position: ScreenCameraOverlayPosition
): Promise<void> {
  if (!broadcastRoom || !isPublishing || role !== "broadcaster") return
  screenCameraOverlayPosition = position
  emit()
  if (!screenCameraOverlayEnabled) return
  try {
    await setScreenCameraOverlayPosition(broadcastRoom, position)
  } catch (err) {
    screenCameraOverlayError =
      err instanceof Error ? err.message : "Could not move overlay."
    emit()
  }
}
