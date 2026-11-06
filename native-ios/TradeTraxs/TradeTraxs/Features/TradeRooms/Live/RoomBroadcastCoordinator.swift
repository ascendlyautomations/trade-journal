import Foundation
import LiveKit
import Observation

struct RoomBroadcastStatus: Hashable, Sendable {
    var isLive: Bool
    var broadcastSessionId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var voiceMode: String?
    var videoSource: String?
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
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isWatching = false
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var chatMessages: [BroadcastChatMessageItem] = []
    private(set) var videoTrack: VideoTrack?
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
    /// Bumped to ask ``RoomBroadcastWatchView`` to exit immersive fullscreen before stream-ended UI.
    private(set) var streamFullscreenDismissSignal: UInt = 0

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
    private var roomDiscoveryPollTask: Task<Void, Never>?
    private var sessionPollTask: Task<Void, Never>?
    private var pollRoomID: RoomID?
    private var currentSessionId: String?
    private var broadcasterIdentity: String?
    private var preferredVideoSource = "screen"
    private var playbackSessionHandle: SessionRequirementHandle?
    private var raisedHandIdentities: Set<String> = [] {
        didSet { broadcastRaisedHandIdentities = raisedHandIdentities }
    }
    private var consecutiveSuccessfulNotLivePolls = 0
    private var isEndingWatchVoluntarily = false
    private var streamEndedPopupPresentedSessionId: String?
    let chatProfileCache = BroadcastChatProfileCache()

    private init() {}

    func acknowledgeStreamEndedNotice() {
        streamEndedNotice = nil
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

    func isWatchingRoom(_ roomID: RoomID) -> Bool {
        isWatching && watchSession?.roomID == roomID
    }

    /// Poll for go-live discovery while a Trade Room conversation is open.
    func startPolling(roomID: RoomID) {
        pollRoomID = roomID
        roomDiscoveryPollTask?.cancel()
        roomDiscoveryPollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatus(roomID: roomID)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self.refreshStatus(roomID: roomID)
            }
        }
    }

    func stopPolling() {
        roomDiscoveryPollTask?.cancel()
        roomDiscoveryPollTask = nil
        pollRoomID = nil
        statusPollRoomID = nil
    }

    func refreshStatus(roomID: RoomID) async {
        guard let client else {
            #if DEBUG
            print("[TradeTraxs Broadcast] status skipped — LiveKitBroadcastClient not configured")
            #endif
            return
        }
        do {
            let res = try await client.fetchStatus(roomID: roomID)
            let next = RoomBroadcastStatus(
                isLive: res.live,
                broadcastSessionId: res.broadcastSessionId,
                broadcasterUserId: res.broadcasterUserId,
                broadcasterDisplayName: res.broadcasterDisplayName,
                voiceMode: res.voiceMode,
                videoSource: res.videoSource,
                viewerCount: res.viewerCount
            )
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] status room=\(roomID.rawValue) live=\(res.live) \
                session=\(res.broadcastSessionId ?? "nil") source=\(res.videoSource ?? "nil")
                """
            )
            #endif
            if pollRoomID == roomID {
                if let sid = next.broadcastSessionId, sid != currentSessionId, !isWatching {
                    chatMessages = []
                }
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
            } else if isWatching, watchSession?.roomID == roomID {
                polledStatus = next
                statusPollRoomID = roomID
                statusPollError = nil
            }

            if isWatching, watchSession?.roomID == roomID {
                consecutiveSuccessfulNotLivePolls = BroadcastStreamEndPolicy.nextConsecutiveNotLivePollCount(
                    pollSucceeded: true,
                    responseLive: res.live,
                    previousCount: consecutiveSuccessfulNotLivePolls
                )
                if shouldEndWatchAfterStatusPoll(roomID: roomID, responseLive: res.live) {
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
        if isWatching, watchSession?.roomID == roomID, connectionState == .connected {
            return
        }

        if isWatching, watchSession?.roomID != roomID {
            await leaveWatch()
        }

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
            startSessionPolling(roomID: roomID)
        } catch {
            lastError = error.localizedDescription
            await teardown()
        }
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
        sessionPollTask?.cancel()
        sessionPollTask = nil
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
            try await connectViewer(roomID: roomID, roomTitle: title, asConversation: true) {
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
                    try? await room.localParticipant.setMicrophone(enabled: false)
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

    private func startSessionPolling(roomID: RoomID) {
        sessionPollTask?.cancel()
        sessionPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self.refreshStatus(roomID: roomID)
            }
        }
    }

    private func connectViewer(
        roomID: RoomID,
        roomTitle: String,
        asConversation: Bool,
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
        preferredVideoSource = token.videoSource ?? "screen"
        watchSession = BroadcastWatchSession(
            roomID: roomID,
            roomTitle: roomTitle,
            voiceMode: token.voiceMode
        )
        if chatMessages.isEmpty {
            chatMessages = []
        }

        applyPlaybackAudioPolicy()

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

        if asConversation, token.canPublish {
            do {
                try await nextRoom.localParticipant.setMicrophone(enabled: true)
                isMicrophoneEnabledInStream = true
            } catch {
                isMicrophoneEnabledInStream = false
                throw error
            }
        } else {
            try? await nextRoom.localParticipant.setMicrophone(enabled: false)
            isMicrophoneEnabledInStream = false
        }

        syncVideoTrack(from: nextRoom)
        syncViewerCount(from: nextRoom)
        applyStreamPlaybackMute()
    }

    private func applyPlaybackAudioPolicy() {
        if RoomLiveVoiceCoordinator.shared.isSessionActive {
            return
        }
        AudioManager.prepare()
        playbackSessionHandle = try? AudioManager.shared.acquireSessionRequirement(.playbackOnly)
    }

    private func releasePlaybackAudio() {
        try? playbackSessionHandle?.release()
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

    private func handleRemoteStreamEnded() async {
        guard !isEndingWatchVoluntarily else { return }
        guard isWatching else { return }
        guard let sessionId = currentSessionId else { return }

        sessionPollTask?.cancel()
        sessionPollTask = nil

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

    private func teardown() async {
        sessionPollTask?.cancel()
        sessionPollTask = nil
        videoTrack = nil
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
        watchSession = nil
        isStreamPlaybackMuted = false
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
        for p in room.remoteParticipants.values {
            if p.identity?.stringValue != broadcasterIdentity {
                count += 1
            }
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
                if isSpeaker, isOpenVoiceStream { return "Speaker" }
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
    }

    private func syncVideoTrack(from room: Room) {
        guard let broadcasterIdentity,
              let participant = room.remoteParticipants.values.first(where: {
                  $0.identity?.stringValue == broadcasterIdentity
              })
        else {
            videoTrack = nil
            return
        }

        let preferScreen = preferredVideoSource != "camera"
        var fallback: VideoTrack?
        for pub in participant.trackPublications.values {
            guard pub.kind == .video, let track = pub.track as? VideoTrack else { continue }
            if pub.source == .screenShareVideo {
                if preferScreen {
                    videoTrack = track
                    return
                }
                fallback = track
            } else if pub.source == .camera {
                if !preferScreen {
                    videoTrack = track
                    return
                }
                fallback = track
            }
        }
        videoTrack = fallback
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
            syncVideoTrack(from: room)
            syncViewerCount(from: room)
            applyStreamPlaybackMute()
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            syncVideoTrack(from: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in syncViewerCount(from: room) }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            syncViewerCount(from: room)
            let identity = participant.identity?.stringValue
            if BroadcastStreamEndPolicy.shouldEndWatchFromBroadcasterDisconnect(
                isWatching: isWatching,
                isVoluntaryLeave: isEndingWatchVoluntarily,
                disconnectedIdentity: identity,
                broadcasterIdentity: broadcasterIdentity
            ) {
                await handleRemoteStreamEnded()
            }
        }
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        Task { @MainActor in
            self.connectionState = connectionState
            guard isWatching, !isEndingWatchVoluntarily else { return }
            guard BroadcastStreamEndPolicy.shouldDeferStreamEndForConnectionState(connectionState) == false else {
                return
            }
            if connectionState == .disconnected,
               oldValue == .connected || oldValue == .reconnecting || oldValue == .disconnecting,
               let roomID = watchSession?.roomID
            {
                await refreshStatus(roomID: roomID)
            }
        }
    }
}
