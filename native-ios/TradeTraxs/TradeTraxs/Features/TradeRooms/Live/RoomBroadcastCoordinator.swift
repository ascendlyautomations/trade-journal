import Foundation
import LiveKit
import Observation

struct RoomBroadcastStatus: Hashable, Sendable {
    /// Discoverable / viewer-accessible live (false during OBS private preparation).
    var isLive: Bool
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var voiceMode: String?
    var videoSource: String?
    /// "browser" or "obs"
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var hostConnected: Bool?
    var primaryMediaPublisherConnected: Bool?
    var viewerCount: Int?
}

struct BroadcastWatchSession: Hashable, Sendable {
    var roomID: RoomID
    var roomTitle: String
    var voiceMode: String?
}

struct BroadcastRosterParticipant: Identifiable, Hashable, Sendable {
    var id: String { identity }
    var identity: String
    var displayName: String
    var roleLabel: String
    var isHandRaised: Bool
    var isLocal: Bool
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
        voiceMode: nil,
        videoSource: nil,
        broadcastSource: nil,
        primaryMediaPublisherIdentity: nil,
        hostConnected: nil,
        primaryMediaPublisherConnected: nil,
        viewerCount: nil
    )
    private(set) var statusPollError: String?
    private(set) var statusPollRoomID: RoomID?
    var isStreamLive: Bool {
        polledStatus.isLive
    }

    func isStreamLive(for roomID: RoomID) -> Bool {
        statusPollRoomID == roomID && polledStatus.isLive
    }

    /// Viewer count from broadcast status poll when the poll targets ``roomID``.
    func liveViewerCount(for roomID: RoomID) -> Int? {
        guard statusPollRoomID == roomID else { return nil }
        guard let count = polledStatus.viewerCount else { return nil }
        return max(0, count)
    }
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isWatching = false
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var chatMessages: [BroadcastChatMessageItem] = []
    private(set) var videoTrack: VideoTrack?
    /// Bumped when the program video track or publication changes so ``VideoView`` rebinds after replaceTrack / program switches.
    private(set) var programVideoTrackRevision: UInt = 0
    private(set) var localViewerCount = 0
    private(set) var isInConversation = false
    private(set) var isMicrophoneEnabledInStream = false
    private(set) var watchSession: BroadcastWatchSession?
    private(set) var isViewerPresented = false
    private(set) var isVideoRenderingEnabled = true
    private(set) var isStreamPlaybackMuted = false
    private(set) var isBroadcastHandRaised = false
    private(set) var rosterParticipants: [BroadcastRosterParticipant] = []
    private(set) var broadcastRaisedHandIdentities: Set<String> = []
    private(set) var streamEndedNotice: BroadcastStreamEndedNotice?
    private(set) var streamRemovalNotice: BroadcastStreamRemovalNotice?
    private(set) var streamConnectionLostNotice: BroadcastStreamConnectionLostNotice?
    private(set) var speakInviteNotice: BroadcastSpeakInviteNotice?
    private(set) var speakInviteActionError: String?
    /// Bumped to ask ``RoomBroadcastWatchView`` to exit immersive fullscreen before stream-ended UI.
    private(set) var streamFullscreenDismissSignal: UInt = 0

    // MARK: - OBS host preview (private prep — separate LiveKit connection from viewer watch)

    private var obsHostPreviewRoom: Room?
    private var obsHostPreviewDelegateBag: ObsHostPreviewRoomDelegate?
    private(set) var obsHostPreviewVideoTrack: VideoTrack?
    private(set) var obsHostPreviewConnectionState: ConnectionState = .disconnected
    private var obsHostPreviewProgramIdentity: String?

    /// Video for UI — nil while minimized so SwiftUI detaches the renderer without disconnecting.
    var videoTrackForDisplay: VideoTrack? {
        isVideoRenderingEnabled ? videoTrack : nil
    }

    var showsBroadcastChrome: Bool {
        BroadcastChromeVisibility.shouldShowBar(
            isWatching: isWatching,
            connectionState: connectionState,
            isBusy: isBusy,
            hasWatchSession: watchSession != nil
        )
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
    private var interactivePollTask: Task<Void, Never>?
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
    let chatProfileCache = BroadcastChatProfileCache()

    private init() {}

    func acknowledgeStreamEndedNotice() {
        streamEndedNotice = nil
    }

    func acknowledgeStreamRemovalNotice() {
        streamRemovalNotice = nil
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
            if !isViewerPresented {
                isVideoRenderingEnabled = true
            }
        } catch {
            speakInviteActionError = error.localizedDescription
        }
    }

    func configure(
        transport: SupabaseTransport,
        profileLookup: (@Sendable ([ProfileID]) async throws -> [Profile])? = nil
    ) {
        client = LiveKitBroadcastClient(transport: transport)
        if let profileLookup {
            chatProfileCache.configure(profileLookup: profileLookup)
        }
    }

    /// Connect as OBS **host** (subscribe-only for program preview + data). Does not enable camera or mic.
    func connectObsHostPreview(
        token: LiveKitBroadcastStartResponse,
        programPublisherIdentity: String?
    ) async throws {
        await disconnectObsHostPreview()
        let nextRoom = Room()
        let bag = ObsHostPreviewRoomDelegate()
        nextRoom.add(delegate: bag)
        obsHostPreviewDelegateBag = bag
        obsHostPreviewRoom = nextRoom
        if let sid = token.broadcastSessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            obsHostPreviewProgramIdentity = BroadcastObsProgramVideo.resolvedProgramPublisherIdentity(
                sessionId: sid,
                primaryFromToken: programPublisherIdentity,
                primaryFromStatus: nil
            )
        } else {
            obsHostPreviewProgramIdentity = programPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
        obsHostPreviewVideoTrack = nil
        obsHostPreviewProgramIdentity = nil
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
        programVideoTrackRevision &+= 1
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

    func stopPolling() {
        roomDiscoveryRefreshTask?.cancel()
        roomDiscoveryRefreshTask = nil
        stopInteractivePolling()
        pollRoomID = nil
        pollRoomTitle = nil
        statusPollRoomID = nil
    }

    func refreshStatus(roomID: RoomID) async {
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
            let res = try await client.fetchStatus(roomID: roomID)
            let vis = res.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let discoverableLive =
                res.publicLive
                ?? (res.live && vis != "preparing")
            let next = RoomBroadcastStatus(
                isLive: discoverableLive,
                broadcastSessionId: res.broadcastSessionId,
                broadcasterUserId: res.broadcasterUserId,
                broadcasterDisplayName: res.broadcasterDisplayName,
                voiceMode: res.voiceMode,
                videoSource: res.videoSource,
                broadcastSource: res.broadcastSource,
                primaryMediaPublisherIdentity: res.primaryMediaPublisherIdentity,
                hostConnected: res.hostConnected,
                primaryMediaPublisherConnected: res.primaryMediaPublisherConnected,
                viewerCount: res.viewerCount
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
                }
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
                if next.isLive {
                    startInteractivePolling(roomID: roomID)
                } else {
                    stopInteractivePolling()
                    speakInviteNotice = nil
                }
            } else if isWatching, watchSession?.roomID == roomID {
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
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
        if isWatching, watchSession?.roomID == roomID, connectionState == .connected {
            syncBroadcastLiveActivity()
            return
        }

        if isWatching, watchSession?.roomID != roomID {
            await leaveWatch()
        }

        broadcastLiveActivityEpoch &+= 1
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
            lastError = error.localizedDescription
            await teardown()
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
        isViewerPresented = true
        isVideoRenderingEnabled = true
    }

    func minimizeViewer() {
        isViewerPresented = false
        isVideoRenderingEnabled = false
    }

    func leaveWatch() async {
        isEndingWatchVoluntarily = true
        defer { isEndingWatchVoluntarily = false }
        isViewerPresented = false
        isVideoRenderingEnabled = true
        consecutiveSuccessfulNotLivePolls = 0
        await teardown()
    }

    func toggleStreamPlaybackMute() async {
        isStreamPlaybackMuted.toggle()
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

    func sendChat(userId: String, displayName: String, avatarUrl: String?, text: String) async {
        guard let room else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let data = try BroadcastChatPayload.encodeOutgoing(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                text: trimmed
            )
            try await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(
                    topic: TradeRoomBroadcastChatConstants.topic,
                    reliable: true
                )
            )
            appendChat(
                BroadcastChatMessageItem(
                    id: "\(userId)-\(Int(Date().timeIntervalSince1970 * 1000))",
                    userId: userId,
                    displayName: displayName,
                    text: trimmed,
                    sentAt: Date()
                )
            )
        } catch {
            lastError = "Could not send chat message."
        }
    }

    private func startInteractivePolling(roomID: RoomID) {
        interactivePollTask?.cancel()
        interactivePollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshInteractiveState(roomID: roomID)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self.refreshInteractiveState(roomID: roomID)
            }
        }
    }

    private func stopInteractivePolling() {
        interactivePollTask?.cancel()
        interactivePollTask = nil
    }

    private func refreshInteractiveState(roomID: RoomID) async {
        guard let client, pollRoomID == roomID, polledStatus.isLive else { return }
        guard let viewerId = interactiveViewerProfileID?.rawValue, !viewerId.isEmpty else { return }
        guard !isInConversation else { return }

        do {
            let response = try await client.fetchInteractiveState(roomID: roomID)
            guard let snapshot = response.snapshot else { return }

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
        if connectionState == .connected {
            TradeTraxsLiveBroadcastLiveActivityManager.shared.start(
                tradeRoomName: session.roomTitle,
                roomID: session.roomID.rawValue,
                sessionEpoch: broadcastLiveActivityEpoch,
                content: content
            )
        } else {
            TradeTraxsLiveBroadcastLiveActivityManager.shared.update(
                sessionEpoch: broadcastLiveActivityEpoch,
                content: content
            )
        }
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
        isViewerPresented = false
        isVideoRenderingEnabled = true

        let roomTitle = watchSession?.roomTitle ?? "Trade Room"
        await teardown()

        guard BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
            isVoluntaryLeave: false,
            alreadyPresentedForSessionId: streamEndedPopupPresentedSessionId,
            sessionId: sessionId
        ) else { return }

        streamEndedPopupPresentedSessionId = sessionId
        streamEndedNotice = BroadcastStreamEndedNotice(sessionId: sessionId, roomTitle: roomTitle)
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

    private func teardown() async {
        let endingEpoch = broadcastLiveActivityEpoch
        TradeTraxsLiveBroadcastLiveActivityManager.shared.end(sessionEpoch: endingEpoch)
        videoTrack = nil
        selectedProgramVideoPublicationSid = nil
        programVideoTrackRevision &+= 1
        preferredVideoSource = "screen"
        chatMessages = []
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
        isStreamPlaybackMuted = false
        speakInviteNotice = nil
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
        let volume: Double = isStreamPlaybackMuted ? 0 : 1
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
            let ids = chatMessages.map(\.userId)
            await chatProfileCache.hydrate(userIds: ids)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            guard publication.kind == .video else { return }
            syncVideoTrack(from: room)
            syncViewerCount(from: room)
            applyStreamPlaybackMute()
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
