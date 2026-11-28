import Foundation
import LiveKit

/// A user-initiated connection to voice, stream viewing, or stream hosting.
enum LiveRealtimeSessionIntent: Hashable, Sendable {
    case voice(roomID: RoomID)
    case streamViewer(roomID: RoomID)
    case streamHost(roomID: RoomID)
}

struct LiveRealtimeSessionSwitchPrompt: Equatable, Sendable {
    var title: String
    var message: String
    var endsActiveBroadcast: Bool
}

/// Single active voice or stream occupancy across TradeTraxs.
@MainActor
enum LiveRealtimeSessionGuard {
    static func requiresLeaveConfirmation(for intent: LiveRealtimeSessionIntent) -> Bool {
        if isReopeningSameSession(intent) {
            return false
        }
        return activeOccupancy() != nil
    }

    static func promptModel(for intent: LiveRealtimeSessionIntent) -> LiveRealtimeSessionSwitchPrompt {
        let endsBroadcast = currentHostingEndsBroadcastOnLeave()
        let message: String
        if endsBroadcast {
            message =
                "Leaving will end your live broadcast. Would you like to leave your current call to join this one?"
        } else {
            message = "Would you like to leave your current call to join this one?"
        }
        return LiveRealtimeSessionSwitchPrompt(
            title: "Leave Current Call?",
            message: message,
            endsActiveBroadcast: endsBroadcast
        )
    }

    static func isReopeningSameSession(_ intent: LiveRealtimeSessionIntent) -> Bool {
        switch intent {
        case .voice(let roomID):
            return RoomLiveVoiceCoordinator.shared.isEngagedInVoice(for: roomID)
                && RoomLiveVoiceCoordinator.shared.connectionState == .connected
        case .streamViewer(let roomID):
            return RoomBroadcastCoordinator.shared.isWatchingRoomConnected(roomID)
        case .streamHost(let roomID):
            let obs = TradeRoomObsBroadcastController.shared
            guard obs.hostContextRoomID == roomID else { return false }
            if obs.phase == .preparing || obs.phase == .livePublic {
                return true
            }
            return RoomBroadcastCoordinator.shared.isObsHostLivePublicWatch
                && RoomBroadcastCoordinator.shared.watchSession?.roomID == roomID
        }
    }

    static func activeOccupancy() -> LiveRealtimeSessionIntent? {
        let voice = RoomLiveVoiceCoordinator.shared
        if let session = voice.session,
           voice.showsVoiceChrome
               || voice.isJoining
               || voice.isLeaving
               || voice.connectionState != .disconnected
        {
            return .voice(roomID: session.roomID)
        }

        let broadcast = RoomBroadcastCoordinator.shared
        if broadcast.isWatching || broadcast.isBusy,
           let session = broadcast.watchSession
        {
            return .streamViewer(roomID: session.roomID)
        }

        let obs = TradeRoomObsBroadcastController.shared
        if obs.phase != .idle,
           let roomID = obs.hostContextRoomID
        {
            return .streamHost(roomID: roomID)
        }

        if broadcast.isObsHostBroadcastBarActive || broadcast.isObsHostLivePublicWatch,
           let roomID = broadcast.watchSession?.roomID ?? obs.hostContextRoomID
        {
            return .streamHost(roomID: roomID)
        }

        return nil
    }

    private static func currentHostingEndsBroadcastOnLeave() -> Bool {
        let obs = TradeRoomObsBroadcastController.shared
        if obs.phase == .livePublic {
            return true
        }
        if obs.phase == .preparing, obs.broadcastSessionId != nil {
            return true
        }
        return RoomBroadcastCoordinator.shared.isObsHostLivePublicWatch
    }

    /// Clears any active voice, viewer, or host session before joining another.
    static func disconnectActiveSessions() async {
        let obs = TradeRoomObsBroadcastController.shared
        let broadcast = RoomBroadcastCoordinator.shared
        let voice = RoomLiveVoiceCoordinator.shared

        if let roomID = obs.hostContextRoomID {
            switch obs.phase {
            case .livePublic:
                await obs.endStream(roomID: roomID)
            case .preparing:
                await obs.cancelObsPreparation(roomID: roomID)
            case .idle:
                break
            }
        }

        if voice.session != nil {
            await voice.leave(reason: .replaced, clearError: true)
        }

        if broadcast.isWatching {
            await broadcast.leaveWatch()
        } else if broadcast.isBusy {
            await broadcast.leaveWatch()
        }

        await broadcast.disconnectObsHostPreview()
    }
}