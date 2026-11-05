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
    var sectionID: RoomChannelID
    var roomTitle: String
    var channelTitle: String
    var canPublish: Bool
}

enum LiveVoiceLeaveReason: Sendable {
    case user
    case sessionEnded
    case replaced
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

    func join(
        roomID: RoomID,
        sectionID: RoomChannelID,
        roomTitle: String,
        channelTitle: String
    ) async {
        if session?.roomID == roomID,
           session?.sectionID == sectionID,
           connectionState == .connected
        {
            return
        }

        if session != nil {
            await leave(reason: .replaced)
        }

        guard let tokenClient else {
            lastError = "Live voice is not configured."
            return
        }

        isJoining = true
        lastError = nil
        defer { isJoining = false }

        do {
            applyAudioPolicyBeforeConnect()

            let tokenResponse = try await tokenClient.fetchVoiceToken(
                roomID: roomID,
                sectionID: sectionID
            )

            let nextRoom = Room()
            nextRoom.add(delegate: self)
            room = nextRoom
            canPublishCurrent = tokenResponse.canPublish

            session = LiveVoiceSessionInfo(
                roomID: roomID,
                sectionID: sectionID,
                roomTitle: roomTitle,
                channelTitle: channelTitle,
                canPublish: tokenResponse.canPublish
            )

            try await nextRoom.connect(
                url: tokenResponse.livekitUrl,
                token: tokenResponse.token
            )
            connectionState = nextRoom.connectionState

            if tokenResponse.canPublish {
                try await nextRoom.localParticipant.setMicrophone(enabled: true)
                isMicrophoneEnabled = true
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
            await leave(reason: .user)
        }
    }

    func leave(reason: LiveVoiceLeaveReason = .user) async {
        _ = reason
        if let room {
            room.remove(delegate: self)
            for participant in room.remoteParticipants.values {
                participant.remove(delegate: self)
            }
            room.localParticipant.remove(delegate: self)
            await room.disconnect()
        }
        room = nil
        session = nil
        connectionState = .disconnected
        isMicrophoneEnabled = false
        canPublishCurrent = false
        participants = []
        notifySessionDidChange()
    }

    func setMuted(_ muted: Bool) async {
        guard let room, canPublishCurrent else { return }
        do {
            try await room.localParticipant.setMicrophone(enabled: !muted)
            isMicrophoneEnabled = !muted
            syncParticipants()
        } catch {
            lastError = error.localizedDescription
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
