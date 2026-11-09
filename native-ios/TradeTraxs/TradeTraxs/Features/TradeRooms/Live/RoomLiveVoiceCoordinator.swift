import AVFoundation
import Foundation
import LiveKit
import Observation

struct LiveVoiceParticipantItem: Identifiable, Hashable, Sendable {
    var id: String { identity }
    var identity: String
    var displayName: String
    var isLocal: Bool
    var isSpeaking: Bool
    var isMuted: Bool
    var isHandRaised: Bool
}

struct LiveVoiceSessionInfo: Hashable, Sendable {
    var roomID: RoomID
    var roomTitle: String
    var channelTitle: String
    var canPublish: Bool
}

enum LiveVoiceLeaveReason: Sendable {
    case user
    case sessionEnded
    case replaced
}

enum TradeRoomGeneralVoice {
    /// Internal LiveKit channel naming — user-facing copy uses ``userChannelTitle``.
    static let channelTitle = "General Voice"
    static let userChannelTitle = "Voice"
}

/// App-scoped live voice session — survives Trade Room navigation and text-channel switches.
@Observable
@MainActor
final class RoomLiveVoiceCoordinator: RoomDelegate, ParticipantDelegate {
    static let shared = RoomLiveVoiceCoordinator()

    private(set) var session: LiveVoiceSessionInfo?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isMicrophoneEnabled = false
    private(set) var isHandRaised = false
    private(set) var participants: [LiveVoiceParticipantItem] = []
    private(set) var lastError: String?
    private(set) var isJoining = false
    private(set) var isLeaving = false

    var showsPersistentBar: Bool {
        showsVoiceChrome
    }

    var showsVoiceChrome: Bool {
        LiveVoiceChromeVisibility.shouldShowBar(
            hasSession: session != nil,
            connectionState: connectionState,
            isLeaving: isLeaving,
            isJoining: isJoining
        )
    }

    var isSessionActive: Bool {
        session != nil && connectionState == .connected
    }

    var isReconnecting: Bool {
        connectionState == .reconnecting
    }

    var participantCount: Int {
        participants.count
    }

    private struct CachedGeneralVoicePresence: Equatable {
        var connectedCount: Int
        var fetchedAt: Date
    }

    private static let generalVoicePresenceTTL: TimeInterval = 60

    private var cachedPresenceByRoom: [RoomID: CachedGeneralVoicePresence] = [:]
    /// Single ensure task per room (covers rapid open/disappear).
    private var presenceEnsureTasks: [RoomID: Task<Void, Never>] = [:]
    /// Dedupes concurrent GET /api/livekit/voice/presence for the same room.
    private var presenceInFlight: [RoomID: Task<Void, Never>] = [:]

    /// Members connected to General Voice (live session count when local user is in voice).
    func generalVoiceConnectedCount(for roomID: RoomID) -> Int? {
        if session?.roomID == roomID, connectionState == .connected {
            return participants.count
        }
        if let cached = cachedPresenceByRoom[roomID] {
            return cached.connectedCount
        }
        return nil
    }

    /// One best-effort presence read when opening a room — no background timer.
    func startGeneralVoicePresencePolling(for roomID: RoomID) {
        presenceEnsureTasks[roomID]?.cancel()
        presenceEnsureTasks[roomID] = Task { @MainActor in
            await self.ensureGeneralVoicePresenceCached(roomID: roomID, force: false)
            self.presenceEnsureTasks.removeValue(forKey: roomID)
        }
    }

    func stopGeneralVoicePresencePolling(for roomID: RoomID) {
        presenceEnsureTasks[roomID]?.cancel()
        presenceEnsureTasks.removeValue(forKey: roomID)
    }

    /// Foreground / tab return: refresh only when cache is older than ~60s.
    func refreshGeneralVoicePresenceIfStale(for roomID: RoomID) async {
        await ensureGeneralVoicePresenceCached(roomID: roomID, force: false)
    }

    private func ensureGeneralVoicePresenceCached(roomID: RoomID, force: Bool) async {
        if isEngagedInVoice(for: roomID) {
            cachedPresenceByRoom.removeValue(forKey: roomID)
            return
        }
        if !force,
           let cached = cachedPresenceByRoom[roomID],
           Date().timeIntervalSince(cached.fetchedAt) < Self.generalVoicePresenceTTL
        {
            return
        }
        if let existing = presenceInFlight[roomID] {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            defer { self.presenceInFlight[roomID] = nil }
            await self.performGeneralVoicePresenceFetch(roomID: roomID)
        }
        presenceInFlight[roomID] = task
        await task.value
    }

    private func performGeneralVoicePresenceFetch(roomID: RoomID) async {
        guard let tokenClient else { return }
        if isEngagedInVoice(for: roomID) {
            cachedPresenceByRoom.removeValue(forKey: roomID)
            return
        }
        do {
            let response = try await tokenClient.fetchVoicePresence(roomID: roomID)
            cachedPresenceByRoom[roomID] = CachedGeneralVoicePresence(
                connectedCount: max(0, response.connectedCount),
                fetchedAt: Date()
            )
        } catch {
            // Best-effort — avoid surfacing transient BFF errors in chrome.
        }
    }

    /// Short status for chrome, Live Activity, and in-room indicators.
    var voiceConnectionStatusLabel: String {
        if isLeaving { return "Leaving…" }
        if isJoining { return "Connecting…" }
        switch connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnecting:
            return "Leaving…"
        case .disconnected:
            return "Disconnected"
        @unknown default:
            return "Voice"
        }
    }

    func isEngagedInVoice(for roomID: RoomID) -> Bool {
        guard session?.roomID == roomID else { return false }
        return showsVoiceChrome
            || connectionState == .connected
            || connectionState == .connecting
            || connectionState == .reconnecting
            || connectionState == .disconnecting
    }

    private var tokenClient: LiveKitTokenClient?
    private var room: Room?
    private var canPublishCurrent = false
    private var operationGeneration: UInt64 = 0
    private var liveActivityEpoch: UInt64 = 0
    private var raisedHandIdentities: Set<String> = []
    private var leaveInFlight: Task<Void, Never>?

    private init() {
        wireLiveActivityIntentBridge()
    }

    func configure(transport: SupabaseTransport) {
        tokenClient = LiveKitTokenClient(transport: transport)
    }

    func join(roomID: RoomID, roomTitle: String) async {
        if isJoining || isLeaving {
            return
        }

        if session?.roomID == roomID, connectionState == .connected {
            return
        }

        if RoomBroadcastCoordinator.shared.isWatchingRoom(roomID) {
            await RoomBroadcastCoordinator.shared.leaveWatch()
        }

        if session != nil {
            await leave(reason: .replaced, clearError: true)
        }

        guard let tokenClient else {
            lastError = "Live voice is not configured."
            return
        }

        let joinGeneration = operationGeneration
        isJoining = true
        lastError = nil
        defer { isJoining = false }

        var joinedRoom: Room?

        do {
            applyAudioPolicyBeforeConnect()

            let tokenResponse = try await tokenClient.fetchVoiceToken(roomID: roomID)
            guard operationGeneration == joinGeneration, !isLeaving else { return }

            let nextRoom = Room()
            nextRoom.add(delegate: self)
            room = nextRoom
            joinedRoom = nextRoom
            canPublishCurrent = tokenResponse.canPublish

            try TradeRoomLiveVoiceAudioSession.shared.activate(
                requiresRecording: tokenResponse.canPublish
            )
            guard operationGeneration == joinGeneration, !isLeaving else {
                await teardownRoom(joinedRoom, clearError: true, liveActivityEpoch: liveActivityEpoch)
                return
            }

            session = LiveVoiceSessionInfo(
                roomID: roomID,
                roomTitle: roomTitle,
                channelTitle: TradeRoomGeneralVoice.userChannelTitle,
                canPublish: tokenResponse.canPublish
            )
            isHandRaised = false
            raisedHandIdentities = []

            try await nextRoom.connect(
                url: tokenResponse.livekitUrl,
                token: tokenResponse.token
            )
            guard operationGeneration == joinGeneration, !isLeaving else {
                await teardownRoom(joinedRoom, clearError: true, liveActivityEpoch: liveActivityEpoch)
                return
            }

            liveActivityEpoch &+= 1

            connectionState = nextRoom.connectionState

            if tokenResponse.canPublish {
                do {
                    try await nextRoom.localParticipant.setMicrophone(enabled: true)
                    isMicrophoneEnabled = true
                } catch {
                    if isMicrophoneAccessError(error) {
                        downgradeToListenOnly(on: nextRoom, error: error)
                    } else {
                        throw error
                    }
                }
            } else {
                isMicrophoneEnabled = false
            }

            nextRoom.localParticipant.add(delegate: self)
            for participant in nextRoom.remoteParticipants.values {
                participant.add(delegate: self)
            }

            syncParticipants()
            notifySessionDidChange()
            syncLiveActivity()
        } catch {
            guard operationGeneration == joinGeneration, !isLeaving else { return }
            lastError = error.localizedDescription
            await teardownRoom(joinedRoom, clearError: false, liveActivityEpoch: liveActivityEpoch)
        }
    }

    func leave(reason: LiveVoiceLeaveReason = .user, clearError: Bool = true) async {
        _ = reason
        if let leaveInFlight {
            await leaveInFlight.value
            return
        }

        let task = Task { @MainActor in
            isLeaving = true
            operationGeneration &+= 1
            lastError = nil

            let activeRoom = room
            let endingEpoch = liveActivityEpoch
            await teardownRoom(activeRoom, clearError: clearError, liveActivityEpoch: endingEpoch)

            isLeaving = false
        }
        leaveInFlight = task
        await task.value
        leaveInFlight = nil
    }

    func leaveWithError(_ message: String) async {
        lastError = message
        await leave(clearError: false)
    }

    func setMuted(_ muted: Bool) async {
        guard let room, canPublishCurrent else { return }
        do {
            try await room.localParticipant.setMicrophone(enabled: !muted)
            isMicrophoneEnabled = !muted
            lastError = nil
            syncParticipants()
            syncLiveActivity()
        } catch {
            if isMicrophoneAccessError(error) {
                downgradeToListenOnly(on: room, error: error)
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    func toggleMute() async {
        await setMuted(isMicrophoneEnabled)
    }

    func toggleHandRaised() async {
        guard let room, let identity = room.localParticipant.identity?.stringValue else { return }
        let next = !isHandRaised
        do {
            let data = try LiveVoiceHandPayload.encodeHandState(identity: identity, raised: next)
            try await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(
                    topic: TradeTraxsLiveVoiceActivityConstants.handSignalTopic,
                    reliable: true
                )
            )
            applyLocalHandState(identity: identity, raised: next)
        } catch {
            lastError = "Could not update raise hand."
        }
    }

    func refreshVoiceChromeAfterForeground() {
        syncLiveActivity()
    }

    func refreshLiveActivityAfterForeground() {
        guard let session else {
            TradeTraxsLiveVoiceLiveActivityManager.shared.end(sessionEpoch: nil)
            return
        }
        TradeTraxsLiveVoiceLiveActivityManager.shared.reconcileAfterForeground(
            sessionEpoch: liveActivityEpoch,
            content: liveActivityContentState(),
            tradeRoomName: session.roomTitle,
            channelName: session.channelTitle
        )
    }

    // MARK: - RoomDelegate

    nonisolated func room(
        _: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from _: ConnectionState
    ) {
        Task { @MainActor in
            self.connectionState = connectionState
            if connectionState == .disconnected, self.session != nil, !self.isLeaving {
                self.releaseLiveVoiceAudio()
                self.session = nil
                self.room = nil
                self.isMicrophoneEnabled = false
                self.isHandRaised = false
                self.raisedHandIdentities = []
                self.canPublishCurrent = false
                self.participants = []
                TradeTraxsLiveVoiceLiveActivityManager.shared.end(sessionEpoch: self.liveActivityEpoch)
                self.notifySessionDidChange()
            }
            self.syncParticipants()
            self.syncLiveActivity()
        }
    }

    nonisolated func room(_: Room, participantDidConnect participant: RemoteParticipant) {
        participant.add(delegate: self)
        Task { @MainActor in
            self.syncParticipants()
            self.syncLiveActivity()
        }
    }

    nonisolated func room(_: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            if let id = participant.identity?.stringValue {
                self.raisedHandIdentities.remove(id)
            }
            self.syncParticipants()
            self.syncLiveActivity()
        }
    }

    nonisolated func room(_: Room, didUpdateSpeakingParticipants speakers: [Participant]) {
        Task { @MainActor in
            _ = speakers
            self.syncParticipants()
        }
    }

    nonisolated func room(
        _: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType _: EncryptionType
    ) {
        guard topic == TradeTraxsLiveVoiceActivityConstants.handSignalTopic else { return }
        Task { @MainActor in
            guard case .handState(let identity, let raised) = LiveVoiceHandPayload.decode(from: data) else {
                return
            }
            self.applyRemoteHandState(identity: identity, raised: raised)
        }
    }

    // MARK: - ParticipantDelegate

    nonisolated func participant(_: Participant, didUpdateIsSpeaking isSpeaking: Bool) {
        Task { @MainActor in
            _ = isSpeaking
            self.syncParticipants()
        }
    }

    nonisolated func participant(_: Participant, trackPublicationDidMute _: TrackPublication) {
        Task { @MainActor in self.syncParticipants() }
    }

    nonisolated func participant(_: Participant, trackPublicationDidUnmute _: TrackPublication) {
        Task { @MainActor in self.syncParticipants() }
    }

    // MARK: - Private

    private func teardownRoom(_ activeRoom: Room?, clearError: Bool, liveActivityEpoch: UInt64) async {
        let presenceRoomID = session?.roomID
        if let activeRoom {
            activeRoom.remove(delegate: self)
            for participant in activeRoom.remoteParticipants.values {
                participant.remove(delegate: self)
            }
            activeRoom.localParticipant.remove(delegate: self)
            await activeRoom.disconnect()
        }
        room = nil
        session = nil
        connectionState = .disconnected
        isMicrophoneEnabled = false
        isHandRaised = false
        raisedHandIdentities = []
        canPublishCurrent = false
        participants = []
        if clearError {
            lastError = nil
        }
        releaseLiveVoiceAudio()
        TradeTraxsLiveVoiceLiveActivityManager.shared.end(sessionEpoch: liveActivityEpoch)
        notifySessionDidChange()
        if let presenceRoomID {
            cachedPresenceByRoom.removeValue(forKey: presenceRoomID)
            Task { @MainActor in
                await self.ensureGeneralVoicePresenceCached(roomID: presenceRoomID, force: true)
            }
        }
    }

    private func downgradeToListenOnly(on activeRoom: Room, error: Error) {
        isMicrophoneEnabled = false
        canPublishCurrent = false
        if var current = session {
            current.canPublish = false
            session = current
        }
        lastError = microphoneUserMessage(error) + " You can still listen to the channel."
        Task { @MainActor in
            _ = try? await activeRoom.localParticipant.setMicrophone(enabled: false)
            do {
                try TradeRoomLiveVoiceAudioSession.shared.updateRequiresRecording(false)
            } catch {
                // Best-effort downgrade after mic failure.
            }
            self.syncParticipants()
            self.syncLiveActivity()
        }
        syncParticipants()
    }

    private func isMicrophoneAccessError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == AVFoundation.AVError.errorDomain {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("not found")
            || message.contains("permission")
            || message.contains("not allowed")
            || message.contains("unavailable")
    }

    private func microphoneUserMessage(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("not found") {
            return "No microphone was found on this device."
        }
        if message.contains("permission") || message.contains("not allowed") {
            return "Microphone access was blocked. Check Settings."
        }
        return "Could not open the microphone."
    }

    private func syncParticipants() {
        guard let room else {
            participants = []
            return
        }
        var items: [LiveVoiceParticipantItem] = [
            mapParticipant(room.localParticipant, isLocal: true),
        ]
        for remote in room.remoteParticipants.values.sorted(by: {
            ($0.identity?.stringValue ?? "") < ($1.identity?.stringValue ?? "")
        }) {
            items.append(mapParticipant(remote, isLocal: false))
        }
        participants = items
    }

    private func mapParticipant(_ participant: Participant, isLocal: Bool) -> LiveVoiceParticipantItem {
        let micPub = participant.firstAudioPublication
        let muted = micPub?.isMuted == true || !participant.isMicrophoneEnabled()
        let identity = participant.identity?.stringValue ?? UUID().uuidString
        let hand = isLocal ? isHandRaised : raisedHandIdentities.contains(identity)
        return LiveVoiceParticipantItem(
            identity: identity,
            displayName: participant.name ?? participant.identity?.stringValue ?? "Guest",
            isLocal: isLocal,
            isSpeaking: participant.isSpeaking,
            isMuted: muted,
            isHandRaised: hand
        )
    }

    private func applyLocalHandState(identity: String, raised: Bool) {
        isHandRaised = raised
        if raised {
            raisedHandIdentities.insert(identity)
        } else {
            raisedHandIdentities.remove(identity)
        }
        syncParticipants()
        syncLiveActivity()
    }

    private func applyRemoteHandState(identity: String, raised: Bool) {
        if raised {
            raisedHandIdentities.insert(identity)
        } else {
            raisedHandIdentities.remove(identity)
        }
        syncParticipants()
        syncLiveActivity()
    }

    private func liveActivityContentState() -> TradeTraxsLiveVoiceActivityAttributes.ContentState {
        let label: String = {
            switch connectionState {
            case .connected: return "Connected"
            case .connecting: return "Connecting…"
            case .reconnecting: return "Reconnecting…"
            case .disconnecting: return "Leaving…"
            case .disconnected: return "Disconnected"
            @unknown default: return "Live voice"
            }
        }()
        return TradeTraxsLiveVoiceActivityAttributes.ContentState(
            connectionLabel: label,
            participantCount: participants.count,
            isMicrophoneEnabled: isMicrophoneEnabled,
            isHandRaised: isHandRaised,
            raisedHandCount: raisedHandIdentities.count
        )
    }

    private func syncLiveActivity() {
        guard let session else { return }
        let content = liveActivityContentState()
        if connectionState == .connected {
            TradeTraxsLiveVoiceLiveActivityManager.shared.start(
                tradeRoomName: session.roomTitle,
                channelName: session.channelTitle,
                sessionEpoch: liveActivityEpoch,
                content: content
            )
        } else {
            TradeTraxsLiveVoiceLiveActivityManager.shared.update(
                sessionEpoch: liveActivityEpoch,
                content: content
            )
        }
    }

    private func wireLiveActivityIntentBridge() {
        LiveVoiceActivityIntentBridge.toggleMute = {
            await RoomLiveVoiceCoordinator.shared.toggleMute()
        }
        LiveVoiceActivityIntentBridge.toggleHand = {
            await RoomLiveVoiceCoordinator.shared.toggleHandRaised()
        }
        LiveVoiceActivityIntentBridge.leaveVoice = {
            await RoomLiveVoiceCoordinator.shared.leave()
        }
    }

    private func applyAudioPolicyBeforeConnect() {
        VoiceMessagePlaybackController.shared.stopAll()
        NotificationCenter.default.post(name: .tradeTraxsLiveVoiceSessionDidChange, object: nil)
    }

    private func notifySessionDidChange() {
        NotificationCenter.default.post(name: .tradeTraxsLiveVoiceSessionDidChange, object: nil)
    }

    private func releaseLiveVoiceAudio() {
        TradeRoomLiveVoiceAudioSession.shared.deactivate()
    }
}
