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
    static let channelTitle = "General Voice"
}

/// App-scoped live voice session — survives Trade Room navigation and text-channel switches.
@Observable
@MainActor
final class RoomLiveVoiceCoordinator: RoomDelegate, ParticipantDelegate {
    static let shared = RoomLiveVoiceCoordinator()

    private(set) var session: LiveVoiceSessionInfo?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isMicrophoneEnabled = false
    private(set) var participants: [LiveVoiceParticipantItem] = []
    private(set) var lastError: String?
    private(set) var isJoining = false

    var showsPersistentBar: Bool {
        session != nil && (connectionState == .connected || connectionState == .connecting)
    }

    var isSessionActive: Bool {
        session != nil && connectionState == .connected
    }

    private var tokenClient: LiveKitTokenClient?
    private var room: Room?
    private var canPublishCurrent = false

    private init() {}

    func configure(transport: SupabaseTransport) {
        tokenClient = LiveKitTokenClient(transport: transport)
    }

    func join(roomID: RoomID, roomTitle: String) async {
        if isJoining {
            return
        }

        if session?.roomID == roomID, connectionState == .connected {
            return
        }

        if session != nil {
            await leave(reason: .replaced, clearError: true)
        }

        guard let tokenClient else {
            lastError = "Live voice is not configured."
            return
        }

        isJoining = true
        lastError = nil
        defer { isJoining = false }

        var joinedRoom: Room?

        do {
            applyAudioPolicyBeforeConnect()

            let tokenResponse = try await tokenClient.fetchVoiceToken(roomID: roomID)

            let nextRoom = Room()
            nextRoom.add(delegate: self)
            room = nextRoom
            joinedRoom = nextRoom
            canPublishCurrent = tokenResponse.canPublish

            session = LiveVoiceSessionInfo(
                roomID: roomID,
                roomTitle: roomTitle,
                channelTitle: TradeRoomGeneralVoice.channelTitle,
                canPublish: tokenResponse.canPublish
            )

            try await nextRoom.connect(
                url: tokenResponse.livekitUrl,
                token: tokenResponse.token
            )
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
        } catch {
            lastError = error.localizedDescription
            await teardownRoom(joinedRoom, clearError: false)
        }
    }

    func leave(reason: LiveVoiceLeaveReason = .user, clearError: Bool = true) async {
        _ = reason
        await teardownRoom(room, clearError: clearError)
    }

    func setMuted(_ muted: Bool) async {
        guard let room, canPublishCurrent else { return }
        do {
            try await room.localParticipant.setMicrophone(enabled: !muted)
            isMicrophoneEnabled = !muted
            lastError = nil
            syncParticipants()
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

    // MARK: - RoomDelegate

    nonisolated func room(
        _: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from _: ConnectionState
    ) {
        Task { @MainActor in
            self.connectionState = connectionState
            if connectionState == .disconnected, self.session != nil {
                self.session = nil
                self.participants = []
                self.notifySessionDidChange()
            }
            self.syncParticipants()
        }
    }

    nonisolated func room(_: Room, participantDidConnect participant: RemoteParticipant) {
        participant.add(delegate: self)
        Task { @MainActor in self.syncParticipants() }
    }

    nonisolated func room(_: Room, participantDidDisconnect _: RemoteParticipant) {
        Task { @MainActor in self.syncParticipants() }
    }

    nonisolated func room(_: Room, didUpdateSpeakingParticipants speakers: [Participant]) {
        Task { @MainActor in
            _ = speakers
            self.syncParticipants()
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

    private func teardownRoom(_ activeRoom: Room?, clearError: Bool) async {
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
        canPublishCurrent = false
        participants = []
        if clearError {
            lastError = nil
        }
        notifySessionDidChange()
    }

    private func downgradeToListenOnly(on activeRoom: Room, error: Error) {
        isMicrophoneEnabled = false
        canPublishCurrent = false
        if var current = session {
            current.canPublish = false
            session = current
        }
        lastError = microphoneUserMessage(error) + " You can still listen to the channel."
        Task {
            try? await activeRoom.localParticipant.setMicrophone(enabled: false)
            await MainActor.run { self.syncParticipants() }
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
        return LiveVoiceParticipantItem(
            identity: participant.identity?.stringValue ?? UUID().uuidString,
            displayName: participant.name ?? participant.identity?.stringValue ?? "Guest",
            isLocal: isLocal,
            isSpeaking: participant.isSpeaking,
            isMuted: muted
        )
    }

    private func applyAudioPolicyBeforeConnect() {
        VoiceMessagePlaybackController.shared.stopAll()
        NotificationCenter.default.post(name: .tradeTraxsLiveVoiceSessionDidChange, object: nil)
    }

    private func notifySessionDidChange() {
        NotificationCenter.default.post(name: .tradeTraxsLiveVoiceSessionDidChange, object: nil)
    }
}
