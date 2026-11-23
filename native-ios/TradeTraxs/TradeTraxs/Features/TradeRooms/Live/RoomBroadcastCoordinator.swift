import Foundation
import LiveKit
import Observation

struct RoomBroadcastStatus: Hashable, Sendable {
    /// Discoverable / viewer-accessible live (false during OBS private preparation).
    var isLive: Bool
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var streamTitle: String?
    var voiceMode: String?
    var videoSource: String?
    /// "browser" or "obs"
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var hostConnected: Bool?
    var primaryMediaPublisherConnected: Bool?
    var viewerCount: Int?
    var expiresAt: String?
}

struct BroadcastWatchSession: Hashable, Sendable {
    var roomID: RoomID
    var roomTitle: String
    var voiceMode: String?
}

struct ObsHostBarSession: Hashable, Sendable {
    var roomID: RoomID
    var roomTitle: String
}

struct BroadcastRosterParticipant: Identifiable, Hashable, Sendable {
    var id: String { identity }
    var identity: String
    var displayName: String
    var roleLabel: String
    var isHandRaised: Bool
    var isLocal: Bool

    /// Trailing roster chrome — omit generic viewers; local row is always **You**.
    var rosterRoleDisplay: String? {
        if isLocal { return "You" }
        switch roleLabel {
        case "Broadcaster": return "Broadcaster"
        case "Speaker": return "Speaker"
        default: return nil
        }
    }
}

@Observable
@MainActor
final class RoomBroadcastCoordinator: RoomDelegate, ParticipantDelegate {
    static let shared = RoomBroadcastCoordinator()

    private(set) var polledStatus: RoomBroadcastStatus = RoomBroadcastStatus(
        isLive: false,
        broadcastSessionId: nil,
        broadcasterUserId: nil,
        broadcasterDisplayName: nil,
        streamTitle: nil,
        voiceMode: nil,
        videoSource: nil,
        broadcastSource: nil,
        primaryMediaPublisherIdentity: nil,
        hostConnected: nil,
        primaryMediaPublisherConnected: nil,
        viewerCount: nil,
        expiresAt: nil
    )
    /// Server-authoritative end time when hosting / polling as broadcaster.
    private(set) var broadcastExpiresAt: String?
    private(set) var statusPollError: String?
    private(set) var statusPollRoomID: RoomID?
    var isStreamLive: Bool {
        polledStatus.isLive
    }

    func isStreamLive(for roomID: RoomID) -> Bool {
        statusPollRoomID == roomID && polledStatus.isLive
    }

    func noteBroadcastExpiresAt(_ expiresAt: String?) {
        broadcastExpiresAt = expiresAt?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Viewer count from broadcast status poll when the poll targets ``roomID``.
    func liveViewerCount(for roomID: RoomID) -> Int? {
        guard statusPollRoomID == roomID else { return nil }
        guard let count = polledStatus.viewerCount else { return nil }
        return max(0, count)
    }

    /// True when the signed-in user is hosting a discoverable OBS broadcast in this room.
    func isCurrentUserObsBroadcaster(for roomID: RoomID, userId: String?) -> Bool {
        Self.matchesCurrentUserObsBroadcast(
            status: polledStatus,
            statusRoomID: statusPollRoomID,
            roomID: roomID,
            userId: userId
        )
    }

    nonisolated static func matchesCurrentUserObsBroadcast(
        status: RoomBroadcastStatus,
        statusRoomID: RoomID?,
        roomID: RoomID,
        userId: String?
    ) -> Bool {
        guard statusRoomID == roomID, status.isLive else { return false }
        guard let userId else { return false }
        let broadcaster = status.broadcasterUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !broadcaster.isEmpty, broadcaster == userId else { return false }
        let videoSource = status.videoSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let broadcastSource = status.broadcastSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return videoSource == "obs" || broadcastSource == "obs"
    }
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isWatching = false
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var chatMessages: [BroadcastChatMessageItem] = []
    /// Scroll + highlight when tapping a reply preview in livestream chat.
    private(set) var broadcastChatScrollRequest: BroadcastChatScrollRequest?
    private(set) var highlightedBroadcastChatMessageID: String?
    private(set) var broadcastChatNavigationNotice: String?
    private var broadcastChatScrollRequestToken: UInt64 = 0
    private(set) var videoTrack: VideoTrack?
    /// Bumped when the program video track or publication changes so ``VideoView`` rebinds after replaceTrack / program switches.
    private(set) var programVideoTrackRevision: UInt = 0
    /// First decoded frame received for the current program publication.
    private(set) var programVideoHasRenderedFrame = false
    /// Used to distinguish startup prep from mid-stream video loss (screen share cancel / track drop).
    private var programVideoWasDisplayedBefore = false
    private(set) var localViewerCount = 0
    private(set) var isInConversation = false
    private(set) var isMicrophoneEnabledInStream = false
    private(set) var watchSession: BroadcastWatchSession?
    private(set) var obsHostBarSession: ObsHostBarSession?
    /// Stable sheet anchor — survives ``clearObsHostBarSession()`` during private OBS prep (see ``syncObsHostBarSession()``).
    private(set) var obsManageStreamPresentation: ObsHostBarSession?
    private(set) var isObsManageStreamPresented = false
    private(set) var viewerPresentation: BroadcastViewerPresentation = .off
    private(set) var miniPlayerCorner: BroadcastMiniPlayerCorner = .bottomTrailing
    private static let miniPlayerCornerDefaultsKey = "tradetraxs_broadcast_mini_player_corner_v1"
    private(set) var isStreamPlaybackMuted = false
    /// 0–1 playback gain. Mute does not change this. Hardware volume stays separate.
    private(set) var streamPlaybackGain: Double = 1
    private(set) var isBroadcastHandRaised = false
    private(set) var rosterParticipants: [BroadcastRosterParticipant] = []
    private(set) var broadcastRaisedHandIdentities: Set<String> = []
    private(set) var streamEndedNotice: BroadcastStreamEndedNotice?
    private(set) var streamRemovalNotice: BroadcastStreamRemovalNotice?
    private(set) var viewerSessionAccessDenied: BroadcastViewerSessionAccessDenied?
    private(set) var streamConnectionLostNotice: BroadcastStreamConnectionLostNotice?
    private(set) var speakInviteNotice: BroadcastSpeakInviteNotice?
    private(set) var speakInviteActionError: String?
    private(set) var broadcastSpeakerGrantUserIds: Set<String> = []
    private(set) var broadcastPendingSpeakInvitationIds: [String: String] = [:]
    private(set) var broadcastSessionBlockUserIds: Set<String> = []
    private(set) var interactiveRaisedHandUserIds: Set<String> = []
    private(set) var broadcastModerationError: String?
    private(set) var broadcastModerationBusyUserId: String?
    /// Bumped to ask ``RoomBroadcastWatchView`` to exit immersive fullscreen before stream-ended UI.
    private(set) var streamFullscreenDismissSignal: UInt = 0

    // MARK: - OBS host preview (private prep — separate LiveKit connection from viewer watch)

    private var obsHostPreviewRoom: Room?
    private var obsHostPreviewDelegateBag: ObsHostPreviewRoomDelegate?
    private(set) var obsHostPreviewVideoTrack: VideoTrack?
    private(set) var obsHostPreviewConnectionState: ConnectionState = .disconnected
    private var obsHostPreviewProgramIdentity: String?
    private var obsHostPreviewSessionId: String?
    private var obsHostPreviewConnectTask: Task<Void, Error>?
    private var obsHostPreviewConnectSessionId: String?
    private var obsHostPreviewConnectFlightId: UUID?

    var isViewerPresented: Bool {
        viewerPresentation == .expanded
    }

    var showsFloatingMiniPlayer: Bool {
        viewerPresentation == .mini && watchSession != nil && (isWatching || isBusy)
    }

    /// Full viewer sheet + OBS manage program surface — never attached while mini player holds the track.
    var videoTrackForExpandedViewer: VideoTrack? {
        guard viewerPresentation == .expanded || isObsManageStreamPresented else { return nil }
        return videoTrack
    }

    /// Floating in-app mini-player — single renderer while minimized.
    var videoTrackForMiniPlayer: VideoTrack? {
        viewerPresentation == .mini ? videoTrack : nil
    }

    /// Legacy alias — use ``videoTrackForExpandedViewer`` or ``videoTrackForMiniPlayer``.
    var videoTrackForDisplay: VideoTrack? {
        videoTrackForExpandedViewer
    }

    var hasDisplayableProgramVideo: Bool {
        videoTrack != nil && programVideoHasRenderedFrame
    }

    var showsProgramVideoSurface: Bool {
        isWatching || isObsManageStreamPresented || showsFloatingMiniPlayer
    }

    var programVideoPlaceholder: BroadcastProgramVideoPlaceholderPresentation? {
        BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: showsProgramVideoSurface,
            isLive: polledStatus.isLive || isWatching,
            hasDisplayableVideo: hasDisplayableProgramVideo,
            connection: BroadcastProgramVideoPresentation.connectionPhase(from: connectionState),
            isJoining: isBusy,
            hostConnected: polledStatus.hostConnected,
            primaryMediaPublisherConnected: polledStatus.primaryMediaPublisherConnected,
            broadcastSourceIsObs: broadcastSourceIsObs,
            videoWasDisplayedBefore: programVideoWasDisplayedBefore
        )
    }

    func markProgramVideoFrameRendered() {
        guard videoTrack != nil, !programVideoHasRenderedFrame else { return }
        programVideoHasRenderedFrame = true
        programVideoWasDisplayedBefore = true
    }

    var isObsHostBroadcastBarActive: Bool {
        BroadcastChromeVisibility.shouldShowObsHostBar(
            hasHostBarSession: obsHostBarSession != nil,
            isLivePublic: TradeRoomObsBroadcastController.shared.phase == .livePublic,
            isManageSheetPresented: isObsManageStreamPresented
        )
    }

    var showsBroadcastChrome: Bool {
        if isObsHostBroadcastBarActive { return true }
        if isWatching || showsFloatingMiniPlayer { return false }
        return BroadcastChromeVisibility.shouldShowBar(
            isWatching: isWatching,
            connectionState: connectionState,
            isBusy: isBusy,
            hasWatchSession: watchSession != nil
        )
    }

    func setMiniPlayerCorner(_ corner: BroadcastMiniPlayerCorner) {
        guard miniPlayerCorner != corner else { return }
        miniPlayerCorner = corner
        UserDefaults.standard.set(corner.rawValue, forKey: Self.miniPlayerCornerDefaultsKey)
    }

    private func restoreMiniPlayerCorner() {
        guard
            let raw = UserDefaults.standard.string(forKey: Self.miniPlayerCornerDefaultsKey),
            let corner = BroadcastMiniPlayerCorner(rawValue: raw)
        else {
            miniPlayerCorner = .bottomTrailing
            return
        }
        miniPlayerCorner = corner
    }

    func setObsHostBarSession(roomID: RoomID, roomTitle: String) {
        let trimmed = roomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        obsHostBarSession = ObsHostBarSession(
            roomID: roomID,
            roomTitle: trimmed.isEmpty ? "Trade Room" : trimmed
        )
    }

    func clearObsHostBarSession() {
        obsHostBarSession = nil
    }

    func openObsManageStream(roomID: RoomID, roomTitle: String) {
        let trimmed = roomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ObsHostBarSession(
            roomID: roomID,
            roomTitle: trimmed.isEmpty ? "Trade Room" : trimmed
        )
        obsManageStreamPresentation = session
        setObsHostBarSession(roomID: roomID, roomTitle: roomTitle)
        TradeRoomObsBroadcastController.shared.noteHostContext(roomID: roomID, roomTitle: roomTitle)
        isObsManageStreamPresented = true
        TradeRoomObsBroadcastDiagnostics.log(
            "sheet.present",
            roomID: roomID,
            detail: "manageStream=open"
        )
    }

    func presentObsManageStreamFromBar() {
        guard let obsHostBarSession else { return }
        obsManageStreamPresentation = obsHostBarSession
        isObsManageStreamPresented = true
        TradeRoomObsBroadcastDiagnostics.log(
            "sheet.present",
            roomID: obsHostBarSession.roomID,
            detail: "manageStream=fromBar"
        )
    }

    func setObsManageStreamPresented(_ presented: Bool) {
        if !presented {
            if let roomID = obsManageStreamPresentation?.roomID {
                TradeRoomObsBroadcastDiagnostics.log(
                    "sheet.dismiss",
                    roomID: roomID,
                    detail: "manageStream=closed"
                )
            }
            obsManageStreamPresentation = nil
        }
        isObsManageStreamPresented = presented
    }

    var broadcastStatusLabel: String {
        if isBusy, !isWatching { return "Connecting…" }
        if !polledStatus.isLive, isWatching { return "Stream ended" }
        switch connectionState {
        case .connected:
            return isInConversation ? "In conversation" : "Listening"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnecting:
            return "Leaving…"
        case .disconnected:
            return "Disconnected"
        @unknown default:
            return "Live"
        }
    }

    var isOpenVoiceStream: Bool {
        (watchSession?.voiceMode ?? polledStatus.voiceMode) == "open_voice"
    }

    private var client: LiveKitBroadcastClient?
    private var room: Room?
    private var roomDiscoveryRefreshTask: Task<Void, Never>?
    private var broadcastSyncTask: Task<Void, Never>?
    private var broadcastRealtimeTask: Task<Void, Never>?
    private var broadcastRefreshDebounceTask: Task<Void, Never>?
    private var broadcastRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var broadcastRealtimeSessionID: String?
    private var broadcastRealtimeLastSignalAt: Date?
    private var interactivePollRoomID: RoomID?
    private var realtimeHub: RealtimeHub?
    private var accessTokenProvider: (@Sendable () async -> String?)?
    /// Dedupes concurrent GET /api/livekit/broadcast/status (foreground + room open, etc.).
    private var isStatusFetchInFlight = false
    private var interactiveViewerProfileID: ProfileID?
    private var dismissedSpeakInviteSessionIds: Set<String> = []
    private var presentedSpeakInviteKeys: Set<String> = []
    private var pollRoomID: RoomID?
    private var pollRoomTitle: String?
    private var currentSessionId: String?
    private var broadcasterIdentity: String?
    /// OBS program feed (LiveKit Ingress) — distinct from host UUID.
    private var programPublisherIdentity: String?
    private var broadcastSourceIsObs = false
    private var preferredVideoSource = "screen"
    private var playbackSessionHandle: SessionRequirementHandle?
    /// Separate from viewer ``playbackSessionHandle`` — OBS host preview uses playback-only audio.
    private var obsHostPreviewPlaybackHandle: SessionRequirementHandle?
    private var raisedHandIdentities: Set<String> = [] {
        didSet { broadcastRaisedHandIdentities = raisedHandIdentities }
    }
    private var consecutiveSuccessfulNotLivePolls = 0
    private var isEndingWatchVoluntarily = false
    private var streamEndedPopupPresentedSessionId: String?
    private var streamRemovalPopupPresentedSessionId: String?
    private var streamConnectionLostPopupPresentedSessionId: String?
    private var selectedProgramVideoPublicationSid: String?
    private var broadcastLiveActivityEpoch: UInt64 = 0
    private var lastInteractiveSnapshotFingerprint: String?
    let chatProfileCache = BroadcastChatProfileCache()
    private var tradesRepository: (any TradeRepository)?
    private var detailPresentationCache: DetailPresentationCache?

    private init() {}

    func acknowledgeStreamEndedNotice() {
        streamEndedNotice = nil
    }

    func acknowledgeStreamRemovalNotice() {
        streamRemovalNotice = nil
    }

    func closeViewerSessionAccessDenied() {
        viewerSessionAccessDenied = nil
        viewerPresentation = .off
    }

    func canPresentViewer(for roomID: RoomID) -> Bool {
        isWatchingRoom(roomID) || viewerSessionAccessDenied?.roomID == roomID
    }

    func acknowledgeStreamConnectionLostNotice() {
        streamConnectionLostNotice = nil
    }

    func retryWatchAfterConnectionLoss() async {
        guard let notice = streamConnectionLostNotice else { return }
        let roomID = notice.roomID
        let title = notice.roomTitle
        acknowledgeStreamConnectionLostNotice()
        await watch(roomID: roomID, roomTitle: title)
    }

    func setInteractiveViewerProfileID(_ profileID: ProfileID?) {
        interactiveViewerProfileID = profileID
    }

    func acknowledgeSpeakInviteActionError() {
        speakInviteActionError = nil
    }

    func acknowledgeBroadcastModerationError() {
        broadcastModerationError = nil
    }

    func isBroadcastSpeaker(userId: String) -> Bool {
        broadcastSpeakerGrantUserIds.contains(userId)
    }

    func hasPendingSpeakInvitation(userId: String) -> Bool {
        broadcastPendingSpeakInvitationIds[userId] != nil
    }

    func isUserBlockedFromBroadcastSession(userId: String) -> Bool {
        broadcastSessionBlockUserIds.contains(userId)
    }

    /// Host/broadcaster moderation — reuses web `/api/livekit/broadcast/moderate`.
    func executeBroadcastModeration(
        roomID: RoomID,
        targetUserId: String,
        action: BroadcastModerationAction,
        blockRejoin: Bool = false,
        chatAnnouncement: String? = nil,
        hostUserId: String?,
        hostDisplayName: String
    ) async {
        guard let client else {
            broadcastModerationError = "Livestream API is not configured."
            return
        }
        guard let sessionId = currentSessionId ?? polledStatus.broadcastSessionId, !sessionId.isEmpty else {
            broadcastModerationError = "No active broadcast session."
            return
        }
        broadcastModerationBusyUserId = targetUserId
        defer { broadcastModerationBusyUserId = nil }
        do {
            _ = try await client.moderateBroadcast(
                roomID: roomID,
                sessionId: sessionId,
                targetUserId: targetUserId,
                action: action,
                blockRejoin: blockRejoin
            )
            broadcastModerationError = nil
            await refreshInteractiveState(roomID: roomID)
            if let chatAnnouncement,
               let hostUserId,
               !chatAnnouncement.isEmpty
            {
                _ = await sendChat(
                    userId: hostUserId,
                    displayName: hostDisplayName,
                    avatarUrl: nil,
                    text: chatAnnouncement
                )
            }
        } catch {
            broadcastModerationError = error.localizedDescription
        }
    }

    func declineSpeakInvitation() async {
        guard let notice = speakInviteNotice else { return }
        speakInviteActionError = nil
        if let invitationId = notice.invitationId, !invitationId.isEmpty, let client {
            do {
                _ = try await client.respondToSpeakInvitation(
                    invitationId: invitationId,
                    accept: false
                )
            } catch {
                speakInviteActionError = error.localizedDescription
            }
        }
        dismissedSpeakInviteSessionIds.insert(notice.sessionId)
        speakInviteNotice = nil
    }

    func acceptSpeakInvitation() async {
        guard let notice = speakInviteNotice else { return }
        guard let client else {
            speakInviteActionError = "Livestream API is not configured."
            return
        }
        if RoomLiveVoiceCoordinator.shared.isSessionActive {
            speakInviteActionError = "Leave General Voice before speaking on the stream."
            return
        }
        guard let invitationId = notice.invitationId, !invitationId.isEmpty else {
            speakInviteActionError = "Invitation is no longer valid."
            return
        }
        guard !isBusy else { return }
        isBusy = true
        speakInviteActionError = nil
        defer { isBusy = false }

        do {
            let roomTitle = watchSession?.roomTitle ?? notice.roomTitle
            // Critical: resolve invitation + LiveKit permissions while the viewer is
            // still connected. `connectViewer` tears down the room before `fetchToken`;
            // if we disconnected first, the backend sees no participant and returns 503
            // ("participant does not exist") from RoomService.updateParticipant.
            let accepted = try await client.respondToSpeakInvitation(
                invitationId: invitationId,
                accept: true
            )
            try await connectViewer(
                roomID: notice.roomID,
                roomTitle: roomTitle,
                asConversation: true,
                enableMicrophoneOnConnect: false
            ) {
                try self.tokenResponseFromInviteAccept(
                    accepted,
                    roomID: notice.roomID
                )
            }
            isInConversation = true
            isMicrophoneEnabledInStream = false
            dismissedSpeakInviteSessionIds.insert(notice.sessionId)
            speakInviteNotice = nil
            if viewerPresentation == .off {
                viewerPresentation = .mini
            }
        } catch {
            speakInviteActionError = error.localizedDescription
        }
    }

    private var openProfileHandler: (@MainActor (ProfileID) -> Void)?
    private var openTradeHandler: (@MainActor (TradeID) -> Void)?
    private(set) var chatSharedTrades: [TradeID: Trade] = [:]
    private(set) var chatSharedTradeLoadFailures: Set<TradeID> = []
    private(set) var broadcastChatComposerError: String?

    func configure(
        transport: SupabaseTransport,
        realtimeHub: RealtimeHub? = nil,
        accessTokenProvider: (@Sendable () async -> String?)? = nil,
        profileLookup: (@Sendable ([ProfileID]) async throws -> [Profile])? = nil,
        tradesRepository: (any TradeRepository)? = nil,
        detailCache: DetailPresentationCache? = nil
    ) {
        client = LiveKitBroadcastClient(transport: transport)
        self.realtimeHub = realtimeHub
        self.accessTokenProvider = accessTokenProvider
        self.tradesRepository = tradesRepository
        detailPresentationCache = detailCache
        if let profileLookup {
            chatProfileCache.configure(profileLookup: profileLookup)
        }
        restoreMiniPlayerCorner()
    }

    func refreshBroadcastSessionAfterForeground() {
        realtimeHub?.resumeIfNeeded()
        guard let roomID = watchSession?.roomID ?? statusPollRoomID ?? pollRoomID else { return }
        Task {
            await refreshStatus(roomID: roomID)
            await refreshInteractiveState(roomID: roomID)
        }
    }

    /// Wired from ``MainTabShellView`` — uses ``NavigationCoordinator/openExternal`` so broadcast stays connected.
    func bindOpenProfile(_ handler: @escaping @MainActor (ProfileID) -> Void) {
        openProfileHandler = handler
    }

    func bindOpenTrade(_ handler: @escaping @MainActor (TradeID) -> Void) {
        openTradeHandler = handler
    }

    @discardableResult
    func openParticipantProfile(userId: String) -> Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let profileID = ProfileID(trimmed)
        guard ProfileIDQueryPolicy.isQueryable(profileID) else { return false }
        guard let openProfileHandler else { return false }
        ExperienceHaptics.play(.selection)
        collapseLivestreamChromeForExternalNavigation()
        openProfileHandler(profileID)
        return true
    }

    /// Viewer minimize + host OBS manage dismiss — playback session stays on tab-shell chrome.
    private func collapseLivestreamChromeForExternalNavigation() {
        if viewerPresentation == .expanded {
            minimizeViewer()
        }
        if isObsManageStreamPresented {
            setObsManageStreamPresented(false)
        }
    }

    /// Connect as OBS **host** (subscribe-only for program preview + data). Does not enable camera or mic.
    func connectObsHostPreview(
        token: LiveKitBroadcastStartResponse,
        programPublisherIdentity: String?
    ) async throws {
        let sessionId = token.broadcastSessionId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSessionId = sessionId?.isEmpty == false ? sessionId : nil

        if let normalizedSessionId,
           obsHostPreviewSessionId == normalizedSessionId,
           let room = obsHostPreviewRoom,
           room.connectionState == .connected
        {
            applyObsHostPreviewProgramIdentity(
                token: token,
                programPublisherIdentity: programPublisherIdentity
            )
            syncObsHostPreviewVideo(from: room)
            return
        }

        if let obsHostPreviewConnectTask,
           obsHostPreviewConnectSessionId == normalizedSessionId
        {
            do {
                try await obsHostPreviewConnectTask.value
            } catch is CancellationError {
                if obsHostPreviewConnectionState == .connected,
                   obsHostPreviewSessionId == normalizedSessionId
                {
                    return
                }
                throw CancellationError()
            } catch {
                if obsHostPreviewConnectionState == .connected,
                   obsHostPreviewSessionId == normalizedSessionId
                {
                    return
                }
                throw error
            }
            return
        }

        let flightId = UUID()
        let connectTask = Task { @MainActor in
            try await self.performObsHostPreviewConnect(
                token: token,
                programPublisherIdentity: programPublisherIdentity
            )
        }
        obsHostPreviewConnectTask = connectTask
        obsHostPreviewConnectSessionId = normalizedSessionId
        obsHostPreviewConnectFlightId = flightId
        defer {
            if obsHostPreviewConnectFlightId == flightId {
                obsHostPreviewConnectTask = nil
                obsHostPreviewConnectSessionId = nil
                obsHostPreviewConnectFlightId = nil
            }
        }
        try await connectTask.value
    }

    private func applyObsHostPreviewProgramIdentity(
        token: LiveKitBroadcastStartResponse,
        programPublisherIdentity: String?
    ) {
        if let sid = token.broadcastSessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            obsHostPreviewProgramIdentity = BroadcastObsProgramVideo.resolvedProgramPublisherIdentity(
                sessionId: sid,
                primaryFromToken: programPublisherIdentity,
                primaryFromStatus: nil
            )
        } else if let programPublisherIdentity {
            obsHostPreviewProgramIdentity = programPublisherIdentity
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func performObsHostPreviewConnect(
        token: LiveKitBroadcastStartResponse,
        programPublisherIdentity: String?
    ) async throws {
        let sessionId = token.broadcastSessionId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSessionId = sessionId?.isEmpty == false ? sessionId : nil

        if let room = obsHostPreviewRoom,
           room.connectionState == .connected,
           obsHostPreviewSessionId == normalizedSessionId
        {
            applyObsHostPreviewProgramIdentity(
                token: token,
                programPublisherIdentity: programPublisherIdentity
            )
            syncObsHostPreviewVideo(from: room)
            return
        }

        if obsHostPreviewSessionId != normalizedSessionId {
            await disconnectObsHostPreview()
        }

        let nextRoom = Room()
        let bag = ObsHostPreviewRoomDelegate()
        nextRoom.add(delegate: bag)
        obsHostPreviewDelegateBag = bag
        obsHostPreviewRoom = nextRoom
        obsHostPreviewSessionId = normalizedSessionId
        applyObsHostPreviewProgramIdentity(
            token: token,
            programPublisherIdentity: programPublisherIdentity
        )
        obsHostPreviewConnectionState = nextRoom.connectionState
        AudioManager.prepare()
        _ = try? obsHostPreviewPlaybackHandle?.release()
        obsHostPreviewPlaybackHandle = try? AudioManager.shared.acquireSessionRequirement(.playbackOnly)
        try await nextRoom.connect(url: token.livekitUrl, token: token.token)
        obsHostPreviewConnectionState = nextRoom.connectionState
        for participant in nextRoom.remoteParticipants.values {
            participant.add(delegate: bag)
        }
        syncObsHostPreviewVideo(from: nextRoom)
        nextRoom.localParticipant.add(delegate: bag)
        _ = try? await nextRoom.localParticipant.setMicrophone(enabled: false)
    }

    func disconnectObsHostPreview() async {
        obsHostPreviewConnectTask?.cancel()
        obsHostPreviewConnectTask = nil
        obsHostPreviewConnectSessionId = nil
        obsHostPreviewConnectFlightId = nil
        obsHostPreviewVideoTrack = nil
        obsHostPreviewProgramIdentity = nil
        obsHostPreviewSessionId = nil
        _ = try? obsHostPreviewPlaybackHandle?.release()
        obsHostPreviewPlaybackHandle = nil
        if let r = obsHostPreviewRoom, let bag = obsHostPreviewDelegateBag {
            r.remove(delegate: bag)
            for p in r.remoteParticipants.values {
                p.remove(delegate: bag)
            }
            r.localParticipant.remove(delegate: bag)
            await r.disconnect()
        }
        obsHostPreviewRoom = nil
        obsHostPreviewDelegateBag = nil
        obsHostPreviewConnectionState = .disconnected
    }

    fileprivate func applyObsHostPreviewConnectionState(_ state: ConnectionState) {
        obsHostPreviewConnectionState = state
    }

    func syncObsHostPreviewVideo(from room: Room) {
        obsHostPreviewVideoTrack = BroadcastObsProgramVideo.pickProgramVideoTrack(
            programPublisherIdentity: obsHostPreviewProgramIdentity,
            from: room
        )
    }

    func obsHostPreviewRoomForSync() -> Room? {
        obsHostPreviewRoom
    }

    private func applyProgramVideoTrack(
        _ track: VideoTrack?,
        publicationSid: String? = nil
    ) {
        let nextPubSid = publicationSid ?? track?.sid?.stringValue
        if track == nil, videoTrack == nil, nextPubSid == selectedProgramVideoPublicationSid {
            return
        }
        if let track, nextPubSid == selectedProgramVideoPublicationSid, videoTrack === track {
            return
        }
        #if DEBUG
        print(
            """
            [TradeTraxs Broadcast] program video apply \
            pubSid=\(nextPubSid ?? "nil") trackSid=\(track?.sid?.stringValue ?? "nil") \
            prevPubSid=\(selectedProgramVideoPublicationSid ?? "nil")
            """
        )
        #endif
        selectedProgramVideoPublicationSid = nextPubSid
        videoTrack = track
        programVideoHasRenderedFrame = false
        programVideoTrackRevision &+= 1
    }

    private func resetProgramVideoDisplayState() {
        programVideoHasRenderedFrame = false
        programVideoWasDisplayedBefore = false
    }

    func isWatchingRoom(_ roomID: RoomID) -> Bool {
        isWatching && watchSession?.roomID == roomID
    }

    func isWatchingRoomConnected(_ roomID: RoomID) -> Bool {
        isWatchingRoom(roomID) && connectionState == .connected
    }

    /// One-shot: fetch stream status when opening a Trade Room (no background polling).
    func startPolling(roomID: RoomID, roomTitle: String? = nil) {
        pollRoomID = roomID
        if let roomTitle, !roomTitle.isEmpty {
            pollRoomTitle = roomTitle
        }
        roomDiscoveryRefreshTask?.cancel()
        roomDiscoveryRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatus(roomID: roomID)
        }
    }

    /// Stops Trade Room conversation–scoped discovery polling.
    /// Keeps interactive + status tracking while the user continues watching via global broadcast chrome.
    func stopPolling() {
        roomDiscoveryRefreshTask?.cancel()
        roomDiscoveryRefreshTask = nil
        pollRoomID = nil
        pollRoomTitle = nil

        if isWatching, let watchRoomID = watchSession?.roomID {
            statusPollRoomID = watchRoomID
            ensureInteractivePolling(for: watchRoomID)
            return
        }

        stopInteractivePolling()
        statusPollRoomID = nil
    }

    func refreshStatus(roomID: RoomID, lite: Bool = false) async {
        guard let client else {
            #if DEBUG
            print("[TradeTraxs Broadcast] status skipped — LiveKitBroadcastClient not configured")
            #endif
            return
        }
        guard !isStatusFetchInFlight else { return }
        isStatusFetchInFlight = true
        defer { isStatusFetchInFlight = false }
        do {
            let res = try await client.fetchStatus(roomID: roomID, lite: lite)
            let vis = res.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let discoverableLive =
                res.publicLive
                ?? (res.live && vis != "preparing")
            let next = RoomBroadcastStatus(
                isLive: discoverableLive,
                broadcastSessionId: res.broadcastSessionId,
                broadcasterUserId: res.broadcasterUserId,
                broadcasterDisplayName: res.broadcasterDisplayName,
                streamTitle: res.streamTitle,
                voiceMode: res.voiceMode,
                videoSource: res.videoSource,
                broadcastSource: res.broadcastSource,
                primaryMediaPublisherIdentity: res.primaryMediaPublisherIdentity,
                hostConnected: res.hostConnected,
                primaryMediaPublisherConnected: res.primaryMediaPublisherConnected,
                viewerCount: res.viewerCount,
                expiresAt: res.expiresAt
            )
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] status room=\(roomID.rawValue) live=\(discoverableLive) \
                apiLive=\(res.live) publicLive=\(String(describing: res.publicLive)) visibility=\(res.visibility ?? "nil") \
                session=\(res.broadcastSessionId ?? "nil") source=\(res.videoSource ?? "nil")
                """
            )
            #endif
            let previousVideoSource = polledStatus.videoSource
            if pollRoomID == roomID {
                if let sid = next.broadcastSessionId, sid != currentSessionId, !isWatching {
                    chatMessages = []
                    chatSharedTrades = [:]
                    chatSharedTradeLoadFailures = []
                    broadcastChatComposerError = nil
                    broadcastChatScrollRequest = nil
                    highlightedBroadcastChatMessageID = nil
                    broadcastChatNavigationNotice = nil
                }
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
                broadcastExpiresAt = next.expiresAt
                if next.isLive {
                    ensureInteractivePolling(for: roomID)
                } else {
                    stopInteractivePolling()
                    speakInviteNotice = nil
                }
            } else if isWatching, watchSession?.roomID == roomID {
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
                if next.isLive {
                    ensureInteractivePolling(for: roomID)
                } else {
                    stopInteractivePolling()
                    speakInviteNotice = nil
                }
            }

            if isWatching, watchSession?.roomID == roomID,
               previousVideoSource != next.videoSource,
               let videoSrc = next.videoSource, !videoSrc.isEmpty
            {
                preferredVideoSource = videoSrc
                if let room {
                    syncVideoTrack(from: room)
                }
            }

            if isWatching, watchSession?.roomID == roomID {
                syncBroadcastLiveActivity()
                consecutiveSuccessfulNotLivePolls = BroadcastStreamEndPolicy.nextConsecutiveNotLivePollCount(
                    pollSucceeded: true,
                    responseLive: discoverableLive,
                    previousCount: consecutiveSuccessfulNotLivePolls
                )
                if shouldEndWatchAfterStatusPoll(roomID: roomID, responseLive: discoverableLive) {
                    await handleRemoteStreamEnded()
                }
            }
        } catch {
            if pollRoomID == roomID {
                statusPollError = error.localizedDescription
                #if DEBUG
                print(
                    """
                    [TradeTraxs Broadcast] status failed room=\(roomID.rawValue) \
                    error=\(error.localizedDescription)
                    """
                )
                #endif
            }
        }
    }

    func watch(roomID: RoomID, roomTitle: String) async {
        guard let client, !isBusy else { return }
        if RoomLiveVoiceCoordinator.shared.isEngagedInVoice(for: roomID) {
            await RoomLiveVoiceCoordinator.shared.leave(reason: .replaced, clearError: true)
        }
        streamRemovalNotice = nil
        viewerSessionAccessDenied = nil
        if isWatching, watchSession?.roomID == roomID, connectionState == .connected {
            syncBroadcastLiveActivity()
            return
        }

        if isWatching, watchSession?.roomID != roomID {
            await leaveWatch()
        }

        if polledStatus.broadcastSessionId == nil || pollRoomID != roomID {
            await refreshStatus(roomID: roomID)
        }

        if let deniedSessionId = await resolveViewerSessionJoinDenial(roomID: roomID) {
            presentViewerSessionAccessDenied(
                roomID: roomID,
                roomTitle: roomTitle,
                sessionId: deniedSessionId
            )
            return
        }

        broadcastLiveActivityEpoch &+= 1
        lastInteractiveSnapshotFingerprint = nil
        watchSession = BroadcastWatchSession(
            roomID: roomID,
            roomTitle: roomTitle,
            voiceMode: polledStatus.voiceMode
        )
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try await connectViewer(roomID: roomID, roomTitle: roomTitle, asConversation: false) {
                try await client.fetchViewerToken(roomID: roomID)
            }
            isInConversation = false
            isMicrophoneEnabledInStream = false
            isBroadcastHandRaised = false
            raisedHandIdentities = []
            syncBroadcastLiveActivity()
        } catch {
            if Self.isViewerRemovedFromSessionError(error) {
                let sessionId = polledStatus.broadcastSessionId ?? currentSessionId ?? ""
                presentViewerSessionAccessDenied(
                    roomID: roomID,
                    roomTitle: roomTitle,
                    sessionId: sessionId
                )
                await teardown(preserveViewerPresentation: true)
            } else {
                lastError = error.localizedDescription
                await teardown()
            }
        }
    }

    func refreshBroadcastLiveActivityAfterForeground() {
        guard isWatching, let session = watchSession else {
            TradeTraxsLiveBroadcastLiveActivityManager.shared.end(sessionEpoch: nil)
            return
        }
        TradeTraxsLiveBroadcastLiveActivityManager.shared.reconcileAfterForeground(
            sessionEpoch: broadcastLiveActivityEpoch,
            content: broadcastLiveActivityContentState(),
            tradeRoomName: session.roomTitle,
            roomID: session.roomID.rawValue
        )
    }

    func presentViewer() {
        viewerPresentation = .expanded
    }

    func minimizeViewer() {
        viewerPresentation = .mini
    }

    func leaveWatch() async {
        isEndingWatchVoluntarily = true
        defer { isEndingWatchVoluntarily = false }
        viewerPresentation = .off
        consecutiveSuccessfulNotLivePolls = 0
        await teardown()
    }

    func toggleStreamPlaybackMute() async {
        isStreamPlaybackMuted.toggle()
        applyStreamPlaybackMute()
    }

    func setStreamPlaybackGain(_ gain: Double) {
        streamPlaybackGain = BroadcastPlaybackLevel.clampedGain(gain)
        applyStreamPlaybackMute()
    }

    func toggleBroadcastHand() async {
        guard let room else { return }
        let identity = room.localParticipant.identity?.stringValue ?? ""
        guard !identity.isEmpty else { return }
        let next = !isBroadcastHandRaised
        do {
            let data = try LiveVoiceHandPayload.encodeHandState(identity: identity, raised: next)
            try await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(
                    topic: TradeRoomBroadcastChatConstants.handTopic,
                    reliable: true
                )
            )
            applyLocalBroadcastHand(identity: identity, raised: next)
            if let sessionId = currentSessionId, let roomID = watchSession?.roomID {
                try? await client?.syncRaisedHand(
                    roomID: roomID,
                    sessionId: sessionId,
                    raised: next
                )
            }
        } catch {
            lastError = "Could not update raise hand."
        }
    }

    func joinConversation() async {
        guard isOpenVoiceStream, let roomID = watchSession?.roomID, let client, !isBusy else { return }
        if RoomLiveVoiceCoordinator.shared.isSessionActive {
            lastError = "Leave General Voice before speaking on the stream."
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let title = watchSession?.roomTitle ?? "Trade Room"
            try await connectViewer(
                roomID: roomID,
                roomTitle: title,
                asConversation: true,
                enableMicrophoneOnConnect: false
            ) {
                try await client.joinConversation(roomID: roomID)
            }
            isInConversation = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func leaveConversation() async {
        guard let roomID = watchSession?.roomID, let client, !isBusy else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let viewerToken = try await client.leaveConversation(roomID: roomID)
            guard let viewerToken else {
                isInConversation = false
                isMicrophoneEnabledInStream = false
                if let room {
                    _ = try? await room.localParticipant.setMicrophone(enabled: false)
                }
                return
            }
            let title = watchSession?.roomTitle ?? "Trade Room"
            try await connectViewer(roomID: roomID, roomTitle: title, asConversation: false) {
                viewerToken
            }
            isInConversation = false
            isMicrophoneEnabledInStream = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleStreamMicrophone() async {
        guard isInConversation, let room else { return }
        if RoomLiveVoiceCoordinator.shared.isSessionActive {
            lastError = "Leave General Voice before using the stream microphone."
            return
        }
        do {
            let next = !isMicrophoneEnabledInStream
            if next {
                applyPlaybackAudioPolicy(mayPublishMicrophone: true)
            }
            try await room.localParticipant.setMicrophone(enabled: next)
            isMicrophoneEnabledInStream = next
        } catch {
            lastError = "Could not update microphone."
        }
    }

    func sendChat(
        userId: String,
        displayName: String,
        avatarUrl: String?,
        text: String,
        imageURL: String? = nil,
        tradeID: TradeID? = nil,
        replyTo: BroadcastChatReplyReference? = nil
    ) async -> BroadcastChatSendResult {
        guard let room else {
            return .failed("Not connected to chat.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImageIntent = imageURL.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let sanitizedImage: String?
        if hasImageIntent {
            guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  BroadcastChatAttachmentPolicy.isAllowedBroadcastImageURL(raw)
            else {
                return .failed("Photo URL isn't valid for livestream chat.")
            }
            sanitizedImage = raw
        } else {
            sanitizedImage = nil
        }

        let sanitizedTrade: TradeID?
        if let tradeID {
            guard BroadcastChatAttachmentPolicy.sanitizedTradeID(tradeID.rawValue) != nil else {
                return .failed("That trade can't be shared in livestream chat.")
            }
            sanitizedTrade = tradeID
        } else {
            sanitizedTrade = nil
        }

        guard !trimmed.isEmpty || sanitizedImage != nil || sanitizedTrade != nil else {
            return .failed("Message is empty.")
        }
        if !trimmed.isEmpty, trimmed.count > TradeRoomBroadcastChatConstants.maxLength {
            return .failed("Message is too long.")
        }
        if let replyTo, !BroadcastChatPayload.isValidReplyReference(replyTo) {
            return .failed("Reply is invalid.")
        }
        do {
            let sentAtMs = Int(Date().timeIntervalSince1970 * 1000)
            let data = try BroadcastChatPayload.encodeOutgoing(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                text: trimmed,
                imageURL: sanitizedImage,
                tradeID: sanitizedTrade,
                replyTo: replyTo
            )
            try await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(
                    topic: TradeRoomBroadcastChatConstants.topic,
                    reliable: true
                )
            )
            broadcastChatComposerError = nil
            let local = BroadcastChatMessageItem(
                id: "\(userId)-\(sentAtMs)",
                userId: userId,
                displayName: displayName,
                text: trimmed,
                sentAt: Date(timeIntervalSince1970: Double(sentAtMs) / 1000),
                imageURL: sanitizedImage,
                tradeID: sanitizedTrade,
                replyTo: replyTo
            )
            appendChat(local)
            if let sanitizedTrade {
                await hydrateBroadcastChatTrade(id: sanitizedTrade)
            }
            return .sent
        } catch {
            let message = "Could not publish chat message."
            broadcastChatComposerError = message
            return .failed(message)
        }
    }

    func isBroadcastChatTradeLoadFailed(_ tradeID: TradeID) -> Bool {
        chatSharedTradeLoadFailures.contains(tradeID)
    }

    @discardableResult
    func openSharedTrade(_ tradeID: TradeID) -> Bool {
        guard let openTradeHandler else { return false }
        ExperienceHaptics.play(.selection)
        collapseLivestreamChromeForExternalNavigation()
        openTradeHandler(tradeID)
        return true
    }

    func hydrateBroadcastChatTradesIfNeeded() async {
        let ids = Set(chatMessages.compactMap(\.tradeID)).filter { chatSharedTrades[$0] == nil }
        guard !ids.isEmpty else { return }
        guard let tradesRepository, let detailPresentationCache else {
            ids.forEach { markBroadcastChatTradeLoadFailed($0) }
            return
        }
        do {
            let trades = try await SessionTradeEntityStore.shared.trades(
                ids: Array(ids),
                detailCache: detailPresentationCache,
                repository: tradesRepository
            )
            var loaded = Set<TradeID>()
            for trade in trades {
                chatSharedTrades[trade.id] = trade
                clearBroadcastChatTradeLoadFailure(trade.id)
                loaded.insert(trade.id)
            }
            for id in ids where !loaded.contains(id) {
                markBroadcastChatTradeLoadFailed(id)
            }
        } catch {
            ids.forEach { markBroadcastChatTradeLoadFailed($0) }
        }
    }

    private func hydrateBroadcastChatTrade(id: TradeID) async {
        guard chatSharedTrades[id] == nil else {
            clearBroadcastChatTradeLoadFailure(id)
            return
        }
        guard let tradesRepository, let detailPresentationCache else {
            markBroadcastChatTradeLoadFailed(id)
            return
        }
        do {
            let trades = try await SessionTradeEntityStore.shared.trades(
                ids: [id],
                detailCache: detailPresentationCache,
                repository: tradesRepository
            )
            if let trade = trades.first {
                chatSharedTrades[id] = trade
                clearBroadcastChatTradeLoadFailure(id)
            } else {
                markBroadcastChatTradeLoadFailed(id)
            }
        } catch {
            markBroadcastChatTradeLoadFailed(id)
        }
    }

    private func markBroadcastChatTradeLoadFailed(_ id: TradeID) {
        chatSharedTradeLoadFailures.insert(id)
    }

    private func clearBroadcastChatTradeLoadFailure(_ id: TradeID) {
        chatSharedTradeLoadFailures.remove(id)
    }

    func scrollToBroadcastChatMessage(id messageID: String) {
        let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard chatMessages.contains(where: { $0.id == trimmed }) else {
            broadcastChatNavigationNotice = "Original message unavailable."
            return
        }
        broadcastChatScrollRequestToken &+= 1
        broadcastChatScrollRequest = BroadcastChatScrollRequest(
            messageID: trimmed,
            token: broadcastChatScrollRequestToken
        )
        highlightedBroadcastChatMessageID = trimmed
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_800))
            if highlightedBroadcastChatMessageID == trimmed {
                highlightedBroadcastChatMessageID = nil
            }
        }
    }

    func acknowledgeBroadcastChatNavigationNotice() {
        broadcastChatNavigationNotice = nil
    }

    func setBroadcastChatComposerError(_ message: String) {
        broadcastChatComposerError = message
    }

    func acknowledgeBroadcastChatComposerError() {
        broadcastChatComposerError = nil
    }

    func stageSharedTradeForChat(_ trade: Trade) {
        chatSharedTrades[trade.id] = trade
        clearBroadcastChatTradeLoadFailure(trade.id)
    }

    private func ensureInteractivePolling(for roomID: RoomID) {
        guard polledStatus.isLive else {
            stopBroadcastSessionSync()
            return
        }
        let trackingPassive = pollRoomID == roomID
        let trackingWatch = isWatching && watchSession?.roomID == roomID
        guard trackingPassive || trackingWatch else { return }
        guard let sessionID = resolvedBroadcastSessionId() else { return }
        startBroadcastSessionSync(roomID: roomID, sessionID: sessionID)
    }

    private func resolvedBroadcastSessionId() -> String? {
        let fromWatch = currentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromWatch, !fromWatch.isEmpty { return fromWatch }
        let fromStatus = polledStatus.broadcastSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromStatus, !fromStatus.isEmpty { return fromStatus }
        return nil
    }

    private func startBroadcastSessionSync(roomID: RoomID, sessionID: String) {
        if let existing = broadcastSyncTask, !existing.isCancelled,
           interactivePollRoomID == roomID,
           broadcastRealtimeSessionID == sessionID
        {
            return
        }
        interactivePollRoomID = roomID
        broadcastSyncTask?.cancel()
        broadcastSyncTask = Task { [weak self] in
            await self?.runBroadcastSessionSync(roomID: roomID, sessionID: sessionID)
        }
    }

    private func runBroadcastSessionSync(roomID: RoomID, sessionID: String) async {
        await startBroadcastRealtimeWatch(roomID: roomID, sessionID: sessionID)
        await refreshInteractiveState(roomID: roomID)
        var lastStatusRefresh = Date.distantPast
        while !Task.isCancelled {
            let stillTracking =
                (pollRoomID == roomID)
                || (isWatching && watchSession?.roomID == roomID)
            guard stillTracking, polledStatus.isLive else { break }
            if broadcastRealtimeSessionID != sessionID,
               let nextSession = resolvedBroadcastSessionId()
            {
                await stopBroadcastRealtimeWatch()
                await startBroadcastRealtimeWatch(roomID: roomID, sessionID: nextSession)
            }
            let healthy = isBroadcastRealtimeHealthy
            let interactiveInterval = BroadcastSessionSyncPolicy.fallbackInteractiveInterval(healthy: healthy)
            try? await Task.sleep(for: .seconds(interactiveInterval))
            guard !Task.isCancelled else { break }
            await refreshInteractiveState(roomID: roomID)
            if isWatching, watchSession?.roomID == roomID {
                let statusInterval = BroadcastSessionSyncPolicy.fallbackStatusInterval(healthy: healthy)
                let now = Date()
                if now.timeIntervalSince(lastStatusRefresh) >= statusInterval {
                    lastStatusRefresh = now
                    await refreshStatus(roomID: roomID, lite: healthy)
                }
            }
        }
    }

    private var isBroadcastRealtimeHealthy: Bool {
        realtimeHub != nil
            && BroadcastSessionSyncPolicy.isRealtimeHealthy(lastSignalAt: broadcastRealtimeLastSignalAt)
    }

    private func startBroadcastRealtimeWatch(roomID: RoomID, sessionID: String) async {
        broadcastRealtimeSessionID = sessionID
        guard let hub = realtimeHub else {
            broadcastRealtimeLastSignalAt = nil
            return
        }
        let token = await accessTokenProvider?()
        guard let token, !token.isEmpty else {
            broadcastRealtimeLastSignalAt = nil
            return
        }
        broadcastRealtimeTask?.cancel()
        if let previous = broadcastRealtimeConsumer {
            await hub.releaseWatch(previous)
            broadcastRealtimeConsumer = nil
        }
        let channel = RealtimeChannelID(kind: .broadcast, topic: sessionID)
        try? await hub.subscriptions.subscribe(channel)
        let watch = hub.watchBroadcastInteractiveSession(
            roomID: roomID,
            sessionID: sessionID,
            accessToken: token,
            debugOwner: "RoomBroadcastCoordinator"
        )
        broadcastRealtimeConsumer = watch.consumer
        broadcastRealtimeTask = Task { [weak self] in
            guard let self else { return }
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                await self.handleBroadcastRealtimeSignal(signal, roomID: roomID)
            }
        }
    }

    private func handleBroadcastRealtimeSignal(_ signal: MessageRealtimeSignal, roomID: RoomID) async {
        broadcastRealtimeLastSignalAt = Date()
        if signal.postgresTable == "room_live_broadcasts", signal.kind != .delete {
            if let payload = signal.recordPayload,
               let ended = BroadcastRealtimeSessionRow.endedAt(from: payload),
               !ended.isEmpty
            {
                await refreshStatus(roomID: roomID)
                return
            }
        }
        scheduleDebouncedInteractiveRefresh(roomID: roomID)
    }

    private func scheduleDebouncedInteractiveRefresh(roomID: RoomID) {
        broadcastRefreshDebounceTask?.cancel()
        broadcastRefreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: BroadcastSessionSyncPolicy.realtimeEventDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshInteractiveState(roomID: roomID)
        }
    }

    private func stopBroadcastRealtimeWatch() async {
        broadcastRealtimeTask?.cancel()
        broadcastRealtimeTask = nil
        broadcastRefreshDebounceTask?.cancel()
        broadcastRefreshDebounceTask = nil
        let consumer = broadcastRealtimeConsumer
        let sessionID = broadcastRealtimeSessionID
        broadcastRealtimeConsumer = nil
        broadcastRealtimeSessionID = nil
        broadcastRealtimeLastSignalAt = nil
        if let hub = realtimeHub, let consumer {
            if let sessionID {
                let channel = RealtimeChannelID(kind: .broadcast, topic: sessionID)
                try? await hub.subscriptions.unsubscribe(channel)
            }
            await hub.releaseWatch(consumer)
        }
    }

    private func stopBroadcastSessionSync() {
        broadcastSyncTask?.cancel()
        broadcastSyncTask = nil
        interactivePollRoomID = nil
        lastInteractiveSnapshotFingerprint = nil
        Task { await stopBroadcastRealtimeWatch() }
    }

    /// Legacy name — ends interactive HTTP sync + Realtime watch.
    private func stopInteractivePolling() {
        stopBroadcastSessionSync()
    }

    private func refreshInteractiveState(roomID: RoomID) async {
        guard let client else { return }
        let trackingRoom =
            (pollRoomID == roomID) || (isWatching && watchSession?.roomID == roomID)
        guard trackingRoom, polledStatus.isLive else { return }

        do {
            let response = try await client.fetchInteractiveState(roomID: roomID)
            guard let snapshot = response.snapshot else { return }

            let fingerprint = interactiveSnapshotFingerprint(snapshot)
            let snapshotUnchanged = fingerprint == lastInteractiveSnapshotFingerprint
            if !snapshotUnchanged {
                lastInteractiveSnapshotFingerprint = fingerprint
                applyInteractiveModerationSnapshot(snapshot, profiles: response.profiles)
                if let room, let broadcasterIdentity {
                    syncRoster(from: room, broadcasterIdentity: broadcasterIdentity)
                }
            }

            guard let viewerId = interactiveViewerProfileID?.rawValue, !viewerId.isEmpty else { return }
            guard !isInConversation else { return }

            if snapshot.blockedFromBroadcastRejoin == true, isWatching {
                let removalSessionId = snapshot.sessionId ?? currentSessionId ?? ""
                let removalTitle = watchSession?.roomTitle ?? pollRoomTitle ?? "Trade Room"
                await leaveWatch()
                presentStreamRemovalNotice(
                    sessionId: removalSessionId,
                    roomTitle: removalTitle,
                    blocked: true
                )
                speakInviteNotice = nil
                return
            }

            guard let sessionId = snapshot.sessionId else { return }
            if dismissedSpeakInviteSessionIds.contains(sessionId) { return }

            let grants = snapshot.speakerGrants ?? []
            let pendingId = snapshot.pendingInvitationForViewer?.invitationId
            let hasGrant = grants.contains(viewerId)
            let invited = pendingId != nil || hasGrant
            guard invited else { return }

            if speakInviteNotice?.sessionId == sessionId { return }

            let inviteKey = "\(sessionId)-\(pendingId ?? "grant")"
            if presentedSpeakInviteKeys.contains(inviteKey) { return }

            let title = watchSession?.roomTitle ?? pollRoomTitle ?? "Trade Room"
            speakInviteNotice = BroadcastSpeakInviteNotice(
                sessionId: sessionId,
                roomID: roomID,
                invitationId: pendingId,
                roomTitle: title
            )
            presentedSpeakInviteKeys.insert(inviteKey)
        } catch {
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] interactive-state failed room=\(roomID.rawValue) \
                error=\(error.localizedDescription)
                """
            )
            #endif
        }
    }

    private func interactiveSnapshotFingerprint(
        _ snapshot: LiveKitBroadcastInteractiveStateResponse.Snapshot
    ) -> String {
        let grants = (snapshot.speakerGrants ?? []).sorted().joined(separator: ",")
        let blocks = (snapshot.sessionBlocks ?? []).sorted().joined(separator: ",")
        let hands = (snapshot.raisedHands ?? []).map(\.userId).sorted().joined(separator: ",")
        let pending = (snapshot.pendingInvitations ?? [])
            .map { "\($0.userId):\($0.invitationId)" }
            .sorted()
            .joined(separator: ",")
        let viewerInvite = snapshot.pendingInvitationForViewer?.invitationId ?? ""
        let sessionId = snapshot.sessionId ?? ""
        let removed = snapshot.removedFromStream == true
        let blocked = snapshot.blockedFromBroadcastRejoin == true
        return "\(sessionId)|\(grants)|\(blocks)|\(hands)|\(pending)|\(viewerInvite)|\(removed)|\(blocked)"
    }

    private func applyInteractiveModerationSnapshot(
        _ snapshot: LiveKitBroadcastInteractiveStateResponse.Snapshot,
        profiles: [LiveKitBroadcastInteractiveStateResponse.ProfileLite]?
    ) {
        broadcastSpeakerGrantUserIds = Set(snapshot.speakerGrants ?? [])
        broadcastSessionBlockUserIds = Set(snapshot.sessionBlocks ?? [])
        var pending: [String: String] = [:]
        for invite in snapshot.pendingInvitations ?? [] {
            let uid = invite.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { continue }
            pending[uid] = invite.invitationId
        }
        broadcastPendingSpeakInvitationIds = pending
        interactiveRaisedHandUserIds = Set((snapshot.raisedHands ?? []).map(\.userId))
        if let profiles, !profiles.isEmpty {
            let ids = profiles.map(\.userId)
            Task { await chatProfileCache.hydrate(userIds: ids) }
        }
    }

    private func tokenResponseFromInviteAccept(
        _ accepted: LiveKitBroadcastInviteRespondResponse,
        roomID: RoomID
    ) throws -> LiveKitBroadcastTokenResponse {
        guard let token = accepted.token, let livekitUrl = accepted.livekitUrl else {
            throw AppError.unknown(message: accepted.error ?? "Invalid speaker token response.")
        }
        return LiveKitBroadcastTokenResponse(
            token: token,
            livekitUrl: livekitUrl,
            roomName: roomID.rawValue,
            role: accepted.role ?? "conversation",
            canPublish: accepted.canPublish ?? true,
            canSubscribe: true,
            canPublishData: true,
            expiresInSeconds: 3600,
            broadcastSessionId: accepted.broadcastSessionId ?? polledStatus.broadcastSessionId,
            broadcasterUserId: accepted.broadcasterUserId ?? polledStatus.broadcasterUserId,
            broadcasterDisplayName: accepted.broadcasterDisplayName ?? polledStatus.broadcasterDisplayName,
            startedAt: accepted.startedAt,
            voiceMode: accepted.voiceMode ?? polledStatus.voiceMode,
            videoSource: accepted.videoSource ?? polledStatus.videoSource,
            broadcastSource: accepted.broadcastSource ?? polledStatus.broadcastSource,
            primaryMediaPublisherIdentity:
                accepted.primaryMediaPublisherIdentity ?? polledStatus.primaryMediaPublisherIdentity
        )
    }

    private func connectViewer(
        roomID: RoomID,
        roomTitle: String,
        asConversation: Bool,
        enableMicrophoneOnConnect: Bool = true,
        fetchToken: () async throws -> LiveKitBroadcastTokenResponse
    ) async throws {
        if room != nil {
            await teardownRoomOnly()
        }

        let token = try await fetchToken()
        guard let sessionId = token.broadcastSessionId,
              let broadcasterId = token.broadcasterUserId
        else {
            throw AppError.unknown(message: "Invalid broadcast token.")
        }

        currentSessionId = sessionId
        broadcasterIdentity = broadcasterId
        broadcastSourceIsObs = BroadcastObsProgramVideo.isObsSession(
            broadcastSource: token.broadcastSource ?? polledStatus.broadcastSource,
            videoSource: token.videoSource ?? polledStatus.videoSource
        )
        if broadcastSourceIsObs {
            programPublisherIdentity = BroadcastObsProgramVideo.resolvedProgramPublisherIdentity(
                sessionId: sessionId,
                primaryFromToken: token.primaryMediaPublisherIdentity,
                primaryFromStatus: polledStatus.primaryMediaPublisherIdentity
            )
        } else {
            programPublisherIdentity = token.primaryMediaPublisherIdentity?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        preferredVideoSource = token.videoSource ?? "screen"
        watchSession = BroadcastWatchSession(
            roomID: roomID,
            roomTitle: roomTitle,
            voiceMode: token.voiceMode
        )
        if chatMessages.isEmpty {
            chatMessages = []
            chatSharedTrades = [:]
            chatSharedTradeLoadFailures = []
            broadcastChatComposerError = nil
            broadcastChatScrollRequest = nil
            highlightedBroadcastChatMessageID = nil
            broadcastChatNavigationNotice = nil
        }

        // LiveKit needs AVAudioSession in playAndRecord when we may publish mic audio
        // (conversation / invited speaker). playbackOnly prevents capture even when
        // setMicrophone(true) appears to succeed.
        applyPlaybackAudioPolicy(mayPublishMicrophone: token.canPublish)

        let nextRoom = Room()
        nextRoom.add(delegate: self)
        room = nextRoom

        try await nextRoom.connect(url: token.livekitUrl, token: token.token)
        connectionState = nextRoom.connectionState
        isWatching = true
        pollRoomID = roomID

        nextRoom.localParticipant.add(delegate: self)
        for participant in nextRoom.remoteParticipants.values {
            participant.add(delegate: self)
        }

        if asConversation, token.canPublish, enableMicrophoneOnConnect {
            do {
                try await nextRoom.localParticipant.setMicrophone(enabled: true)
                isMicrophoneEnabledInStream = true
            } catch {
                isMicrophoneEnabledInStream = false
                lastError = "Microphone permission is required to speak on the stream."
            }
        } else {
            _ = try? await nextRoom.localParticipant.setMicrophone(enabled: false)
            isMicrophoneEnabledInStream = false
        }

        syncVideoTrack(from: nextRoom)
        syncViewerCount(from: nextRoom)
        applyStreamPlaybackMute()
        syncBroadcastLiveActivity()
        if polledStatus.isLive {
            ensureInteractivePolling(for: roomID)
        }
    }

    private func broadcastLiveActivityContentState() -> TradeTraxsLiveBroadcastActivityAttributes.ContentState {
        let viewerCount = max(
            localViewerCount,
            polledStatus.viewerCount ?? 0
        )
        return TradeTraxsLiveBroadcastActivityAttributes.ContentState(
            connectionLabel: broadcastStatusLabel,
            viewerCount: viewerCount,
            isLive: polledStatus.isLive && isWatching
        )
    }

    private func syncBroadcastLiveActivity() {
        guard isWatching, let session = watchSession else {
            TradeTraxsLiveBroadcastLiveActivityManager.shared.end(sessionEpoch: broadcastLiveActivityEpoch)
            return
        }
        let content = broadcastLiveActivityContentState()
        if !content.isLive {
            TradeTraxsLiveBroadcastLiveActivityManager.shared.end(sessionEpoch: broadcastLiveActivityEpoch)
            return
        }
        TradeTraxsLiveBroadcastLiveActivityManager.shared.sync(
            tradeRoomName: session.roomTitle,
            roomID: session.roomID.rawValue,
            sessionEpoch: broadcastLiveActivityEpoch,
            content: content,
            allowNewActivity: connectionState == .connected
        )
    }

    private func applyPlaybackAudioPolicy(mayPublishMicrophone: Bool) {
        if RoomLiveVoiceCoordinator.shared.isSessionActive {
            return
        }
        AudioManager.prepare()
        let requirement: SessionRequirement = mayPublishMicrophone
            ? .playbackAndRecording
            : .playbackOnly
        if mayPublishMicrophone {
            AudioManager.shared.isSpeakerOutputPreferred = true
            AudioManager.shared.sessionConfiguration = .playAndRecordSpeaker
        }
        _ = try? playbackSessionHandle?.release()
        playbackSessionHandle = try? AudioManager.shared.acquireSessionRequirement(requirement)
    }

    private func releasePlaybackAudio() {
        _ = try? playbackSessionHandle?.release()
        playbackSessionHandle = nil
    }

    private func shouldEndWatchAfterStatusPoll(roomID: RoomID, responseLive: Bool) -> Bool {
        let watchRoomID = watchSession?.roomID
        if BroadcastStreamEndPolicy.shouldEndWatchFromStatusPoll(
            isWatching: isWatching,
            watchRoomID: watchRoomID,
            polledRoomID: roomID,
            responseLive: responseLive,
            pollSucceeded: true,
            consecutiveSuccessfulNotLivePolls: consecutiveSuccessfulNotLivePolls
        ) {
            return true
        }
        return BroadcastStreamEndPolicy.shouldEndWatchFromStatusPollWhileDisconnected(
            isWatching: isWatching,
            watchRoomID: watchRoomID,
            polledRoomID: roomID,
            responseLive: responseLive,
            pollSucceeded: true,
            connectionState: connectionState,
            consecutiveSuccessfulNotLivePolls: consecutiveSuccessfulNotLivePolls
        )
    }

    private func presentViewerSessionAccessDenied(roomID: RoomID, roomTitle: String, sessionId: String) {
        let resolvedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        viewerSessionAccessDenied = BroadcastViewerSessionAccessDenied(
            roomID: roomID,
            roomTitle: roomTitle,
            sessionId: resolvedSessionId.isEmpty ? "session" : resolvedSessionId
        )
        lastError = nil
        isBusy = false
    }

    private func resolveViewerSessionJoinDenial(roomID: RoomID) async -> String? {
        guard let client else { return nil }
        if let viewerId = interactiveViewerProfileID?.rawValue,
           broadcastSessionBlockUserIds.contains(viewerId),
           polledStatus.isLive,
           (pollRoomID == roomID || statusPollRoomID == roomID)
        {
            return polledStatus.broadcastSessionId
        }

        guard polledStatus.isLive else { return nil }

        do {
            let response = try await client.fetchInteractiveState(roomID: roomID)
            guard let snapshot = response.snapshot else { return nil }
            applyInteractiveModerationSnapshot(snapshot, profiles: response.profiles)
            guard BroadcastViewerJoinAccessGate.isJoinDenied(
                snapshot: snapshot,
                activeSessionId: polledStatus.broadcastSessionId,
                viewerUserId: interactiveViewerProfileID?.rawValue
            ) else {
                return nil
            }
            let sessionId = snapshot.sessionId ?? polledStatus.broadcastSessionId ?? ""
            return sessionId.isEmpty ? polledStatus.broadcastSessionId : sessionId
        } catch {
            return nil
        }
    }

    private static func isViewerRemovedFromSessionError(_ error: Error) -> Bool {
        if error is LiveKitBroadcastAccessError {
            return true
        }
        if case AppError.unknown(let message) = error {
            let normalized = message.lowercased()
            if normalized.contains("removed_from_stream") {
                return true
            }
            if normalized.contains("you have been removed from this livestream") {
                return true
            }
        }
        return false
    }

    private func presentStreamRemovalNotice(sessionId: String, roomTitle: String, blocked: Bool) {
        guard BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
            isVoluntaryLeave: false,
            alreadyPresentedForSessionId: streamRemovalPopupPresentedSessionId,
            sessionId: sessionId
        ) else {
            lastError = blocked
                ? "You were removed from this stream and blocked from rejoining."
                : "You were removed from this stream."
            return
        }
        streamRemovalPopupPresentedSessionId = sessionId
        streamRemovalNotice = BroadcastStreamRemovalNotice(
            sessionId: sessionId,
            roomTitle: roomTitle,
            blocked: blocked
        )
        streamFullscreenDismissSignal &+= 1
        lastError = blocked
            ? "You were removed from this stream and blocked from rejoining."
            : "You were removed from this stream."
    }

    private func handleRemoteStreamEnded() async {
        guard !isEndingWatchVoluntarily else { return }
        guard isWatching else { return }
        guard let sessionId = currentSessionId else { return }

        streamFullscreenDismissSignal &+= 1
        viewerPresentation = .off

        let roomTitle = watchSession?.roomTitle ?? "Trade Room"
        await teardown()

        guard BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
            isVoluntaryLeave: false,
            alreadyPresentedForSessionId: streamEndedPopupPresentedSessionId,
            sessionId: sessionId
        ) else { return }

        streamEndedPopupPresentedSessionId = sessionId
        let durationEnded =
            polledStatus.expiresAt != nil
            && BroadcastDurationLimitSupport.isPastExpiry(polledStatus.expiresAt)
        streamEndedNotice = BroadcastStreamEndedNotice(
            sessionId: sessionId,
            roomTitle: roomTitle,
            detailMessage: durationEnded ? BroadcastDurationLimitSupport.viewerEndedMessage : nil
        )
        consecutiveSuccessfulNotLivePolls = 0
    }

    /// After LiveKit drops the viewer (e.g. moderator removed the participant) while the stream is still live.
    private func handleViewerLiveKitDisconnect(roomID: RoomID, sessionId: String) async {
        guard let client else {
            await suspendLiveKitWatchForReconnect()
            presentStreamConnectionLostIfNeeded(roomID: roomID, sessionId: sessionId)
            return
        }

        await refreshStatus(roomID: roomID)

        let title = watchSession?.roomTitle ?? pollRoomTitle ?? "Trade Room"
        let response = try? await client.fetchInteractiveState(roomID: roomID)
        let action = BroadcastViewerDisconnectClassification.classify(
            watchingSessionId: sessionId,
            statusLive: polledStatus.isLive,
            statusSessionId: polledStatus.broadcastSessionId,
            snapshot: response?.snapshot,
            viewerUserId: interactiveViewerProfileID?.rawValue
        )

        switch action {
        case .streamEnded:
            await handleRemoteStreamEnded()
        case .removed(let blocked):
            await leaveWatch()
            presentStreamRemovalNotice(
                sessionId: response?.snapshot?.sessionId ?? sessionId,
                roomTitle: title,
                blocked: blocked
            )
        case .connectionLost:
            await suspendLiveKitWatchForReconnect()
            presentStreamConnectionLostIfNeeded(roomID: roomID, sessionId: sessionId)
        }
    }

    private func suspendLiveKitWatchForReconnect() async {
        videoTrack = nil
        selectedProgramVideoPublicationSid = nil
        resetProgramVideoDisplayState()
        programVideoTrackRevision &+= 1
        await teardownRoomOnly()
        connectionState = .disconnected
        isWatching = false
        releasePlaybackAudio()
    }

    private func presentStreamConnectionLostIfNeeded(roomID: RoomID, sessionId: String) {
        let roomTitle = watchSession?.roomTitle ?? pollRoomTitle ?? "Trade Room"
        guard BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
            isVoluntaryLeave: isEndingWatchVoluntarily,
            alreadyPresentedForSessionId: streamConnectionLostPopupPresentedSessionId,
            sessionId: sessionId
        ) else { return }
        streamConnectionLostPopupPresentedSessionId = sessionId
        streamFullscreenDismissSignal &+= 1
        streamConnectionLostNotice = BroadcastStreamConnectionLostNotice(
            roomID: roomID,
            sessionId: sessionId,
            roomTitle: roomTitle
        )
        lastError = "Connection to the livestream was lost."
    }

    private func teardown(preserveViewerPresentation: Bool = false) async {
        let endingEpoch = broadcastLiveActivityEpoch
        TradeTraxsLiveBroadcastLiveActivityManager.shared.end(sessionEpoch: endingEpoch)
        videoTrack = nil
        selectedProgramVideoPublicationSid = nil
        resetProgramVideoDisplayState()
        programVideoTrackRevision &+= 1
        preferredVideoSource = "screen"
        chatMessages = []
        chatSharedTrades = [:]
        chatSharedTradeLoadFailures = []
        broadcastChatComposerError = nil
        broadcastChatScrollRequest = nil
        highlightedBroadcastChatMessageID = nil
        broadcastChatNavigationNotice = nil
        chatProfileCache.clear()
        isWatching = false
        isInConversation = false
        isMicrophoneEnabledInStream = false
        isBroadcastHandRaised = false
        raisedHandIdentities = []
        connectionState = .disconnected
        localViewerCount = 0
        currentSessionId = nil
        broadcasterIdentity = nil
        programPublisherIdentity = nil
        broadcastSourceIsObs = false
        watchSession = nil
        if !preserveViewerPresentation {
            viewerPresentation = .off
        }
        isStreamPlaybackMuted = false
        streamPlaybackGain = 1
        speakInviteNotice = nil
        broadcastSpeakerGrantUserIds = []
        broadcastPendingSpeakInvitationIds = [:]
        broadcastSessionBlockUserIds = []
        interactiveRaisedHandUserIds = []
        broadcastModerationError = nil
        broadcastModerationBusyUserId = nil
        stopInteractivePolling()
        releasePlaybackAudio()
        await teardownRoomOnly()
    }

    private func teardownRoomOnly() async {
        if let room {
            room.remove(delegate: self)
            await room.disconnect()
        }
        room = nil
    }

    private func applyStreamPlaybackMute() {
        guard let room else { return }
        let volume = BroadcastPlaybackLevel.trackVolume(
            muted: isStreamPlaybackMuted,
            gain: streamPlaybackGain
        )
        for participant in room.remoteParticipants.values {
            for pub in participant.audioTracks {
                if let track = pub.track as? RemoteAudioTrack {
                    track.volume = volume
                }
            }
        }
    }

    private func applyLocalBroadcastHand(identity: String, raised: Bool) {
        isBroadcastHandRaised = raised
        if raised {
            raisedHandIdentities.insert(identity)
        } else {
            raisedHandIdentities.remove(identity)
        }
        if let room, let broadcasterIdentity {
            syncRoster(from: room, broadcasterIdentity: broadcasterIdentity)
        }
    }

    private func applyRemoteBroadcastHand(identity: String, raised: Bool) {
        if raised {
            raisedHandIdentities.insert(identity)
        } else {
            raisedHandIdentities.remove(identity)
        }
        if let room, let broadcasterIdentity {
            syncRoster(from: room, broadcasterIdentity: broadcasterIdentity)
        }
    }

    private func appendChat(_ item: BroadcastChatMessageItem) {
        chatMessages.append(item)
        if chatMessages.count > TradeRoomBroadcastChatConstants.maxMessages {
            chatMessages.removeFirst(chatMessages.count - TradeRoomBroadcastChatConstants.maxMessages)
        }
    }

    private func syncViewerCount(from room: Room) {
        guard let broadcasterIdentity else {
            localViewerCount = 0
            rosterParticipants = []
            return
        }
        var count = 0
        if room.localParticipant.identity?.stringValue != broadcasterIdentity {
            count += 1
        }
        let programId = programPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in room.remoteParticipants.values {
            let id = p.identity?.stringValue ?? ""
            if id == broadcasterIdentity { continue }
            if broadcastSourceIsObs, let programId, !programId.isEmpty, id == programId {
                continue
            }
            count += 1
        }
        localViewerCount = count
        syncRoster(from: room, broadcasterIdentity: broadcasterIdentity)
    }

    private func syncRoster(from room: Room, broadcasterIdentity: String) {
        var items: [BroadcastRosterParticipant] = []
        let localIdentity = room.localParticipant.identity?.stringValue ?? ""

        func appendParticipant(identity: String, name: String, isLocal: Bool) {
            let isBroadcaster = identity == broadcasterIdentity
            let micPub = isLocal
                ? room.localParticipant.audioTracks.first(where: { $0.source == .microphone })
                : room.remoteParticipants.values
                    .first(where: { $0.identity?.stringValue == identity })?
                    .audioTracks.first(where: { $0.source == .microphone })
            let isSpeaker = micPub?.track != nil && micPub?.isMuted == false
            let role: String = {
                if isBroadcaster { return "Broadcaster" }
                if broadcastSpeakerGrantUserIds.contains(identity) { return "Speaker" }
                if isSpeaker, isOpenVoiceStream || isInConversation { return "Speaker" }
                return "Viewer"
            }()
            items.append(
                BroadcastRosterParticipant(
                    identity: identity,
                    displayName: name.isEmpty ? identity : name,
                    roleLabel: role,
                    isHandRaised: raisedHandIdentities.contains(identity),
                    isLocal: isLocal
                )
            )
        }

        appendParticipant(
            identity: localIdentity,
            name: room.localParticipant.name ?? localIdentity,
            isLocal: true
        )
        for participant in room.remoteParticipants.values {
            let identity = participant.identity?.stringValue ?? UUID().uuidString
            if identity == localIdentity { continue }
            appendParticipant(
                identity: identity,
                name: participant.name ?? identity,
                isLocal: false
            )
        }
        items.sort { lhs, rhs in
            if lhs.roleLabel == "Broadcaster" { return true }
            if rhs.roleLabel == "Broadcaster" { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        rosterParticipants = items
        syncBroadcastLiveActivity()
    }

    private func syncVideoTrack(from room: Room) {
        if broadcastSourceIsObs {
            let track = BroadcastObsProgramVideo.pickProgramVideoTrack(
                programPublisherIdentity: programPublisherIdentity,
                from: room
            )
            applyProgramVideoTrack(track)
            return
        }

        guard let broadcasterIdentity else {
            applyProgramVideoTrack(nil)
            return
        }

        if let picked = BroadcastBrowserProgramVideo.pickProgramVideoTrack(
            broadcasterIdentity: broadcasterIdentity,
            from: room
        ) {
            applyProgramVideoTrack(
                picked.track,
                publicationSid: picked.publicationSid
            )
        } else {
            applyProgramVideoTrack(nil)
        }
    }

    // MARK: - RoomDelegate

    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType _: EncryptionType
    ) {
        Task { @MainActor in
            if topic == TradeRoomBroadcastChatConstants.handTopic {
                guard case .handState(let identity, let raised) = LiveVoiceHandPayload.decode(from: data) else {
                    return
                }
                applyRemoteBroadcastHand(identity: identity, raised: raised)
                return
            }
            guard topic == TradeRoomBroadcastChatConstants.topic else { return }
            let identity = participant?.identity?.stringValue ?? room.localParticipant.identity?.stringValue ?? ""
            guard let msg = BroadcastChatPayload.parseIncoming(data: data, senderIdentity: identity) else {
                return
            }
            appendChat(msg)
            if let tradeID = msg.tradeID {
                await hydrateBroadcastChatTrade(id: tradeID)
            }
            let ids = chatMessages.map(\.userId)
            await chatProfileCache.hydrate(userIds: ids)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            let kind: BroadcastPlaybackLevel.SubscribeKind = {
                switch publication.kind {
                case .audio: return .audio
                case .video: return .video
                default: return .other
                }
            }()
            if kind == .video {
                syncVideoTrack(from: room)
                syncViewerCount(from: room)
            }
            if BroadcastPlaybackLevel.shouldApplyPlayback(on: kind) {
                applyStreamPlaybackMute()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            guard publication.kind == .video else { return }
            syncVideoTrack(from: room)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            guard publication.kind == .video else { return }
            syncVideoTrack(from: room)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            guard publication.kind == .video else { return }
            syncVideoTrack(from: room)
        }
    }

    nonisolated func participant(
        _ participant: RemoteParticipant,
        trackPublication: RemoteTrackPublication,
        didUpdateStreamState streamState: StreamState
    ) {
        Task { @MainActor in
            guard let room, participant.identity?.stringValue == broadcasterIdentity else { return }
            guard trackPublication.kind == .video else { return }
            if streamState == .active {
                syncVideoTrack(from: room)
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            participant.add(delegate: self)
            syncVideoTrack(from: room)
            syncViewerCount(from: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            syncViewerCount(from: room)
            let identity = participant.identity?.stringValue
            if BroadcastStreamEndPolicy.shouldEndWatchFromBroadcasterDisconnect(
                isWatching: isWatching,
                isVoluntaryLeave: isEndingWatchVoluntarily,
                disconnectedIdentity: identity,
                broadcasterIdentity: broadcasterIdentity,
                broadcastSourceIsObs: broadcastSourceIsObs
            ) {
                await handleRemoteStreamEnded()
            }
        }
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        Task { @MainActor in
            self.connectionState = connectionState
            syncBroadcastLiveActivity()
            guard isWatching, !isEndingWatchVoluntarily else { return }
            guard BroadcastStreamEndPolicy.shouldDeferStreamEndForConnectionState(connectionState) == false else {
                return
            }
            if connectionState == .disconnected,
               oldValue == .connected || oldValue == .reconnecting || oldValue == .disconnecting,
               let roomID = watchSession?.roomID,
               let sessionId = currentSessionId
            {
                await handleViewerLiveKitDisconnect(roomID: roomID, sessionId: sessionId)
            }
        }
    }
}

// MARK: - OBS host preview LiveKit delegate (isolated from viewer `RoomDelegate`)

/// LiveKit invokes these callbacks off the main actor; hop to ``RoomBroadcastCoordinator`` (@MainActor singleton).
private final class ObsHostPreviewRoomDelegate: NSObject, RoomDelegate, ParticipantDelegate {
    nonisolated func room(
        _ room: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from _: ConnectionState
    ) {
        Task { @MainActor in
            RoomBroadcastCoordinator.shared.applyObsHostPreviewConnectionState(connectionState)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack _: RemoteTrackPublication) {
        Task { @MainActor in
            let owner = RoomBroadcastCoordinator.shared
            guard owner.obsHostPreviewRoomForSync() === room else { return }
            owner.syncObsHostPreviewVideo(from: room)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack _: RemoteTrackPublication) {
        Task { @MainActor in
            let owner = RoomBroadcastCoordinator.shared
            guard owner.obsHostPreviewRoomForSync() === room else { return }
            owner.syncObsHostPreviewVideo(from: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            let owner = RoomBroadcastCoordinator.shared
            guard owner.obsHostPreviewRoomForSync() === room else { return }
            owner.syncObsHostPreviewVideo(from: room)
        }
    }
}
