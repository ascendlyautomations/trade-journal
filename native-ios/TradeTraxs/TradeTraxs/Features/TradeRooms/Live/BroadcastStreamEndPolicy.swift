import Foundation
import LiveKit

/// Pure rules for when a remote broadcast end should tear down the session vs. be ignored.
enum BroadcastStreamEndPolicy {
    enum EndSignal: Equatable, Sendable {
        case statusPollNotLive(consecutiveSuccessfulNotLivePolls: Int)
        case broadcasterDisconnected
        case liveKitDisconnectedAfterConnected
    }

    /// Successful status responses reporting `live == false` while watching (not poll transport errors).
    static func shouldEndWatchFromStatusPoll(
        isWatching: Bool,
        watchRoomID: RoomID?,
        polledRoomID: RoomID,
        responseLive: Bool,
        pollSucceeded: Bool,
        consecutiveSuccessfulNotLivePolls: Int,
        confirmationThreshold: Int = 2
    ) -> Bool {
        guard pollSucceeded, isWatching else { return false }
        guard watchRoomID == polledRoomID else { return false }
        if responseLive { return false }
        return consecutiveSuccessfulNotLivePolls >= confirmationThreshold
    }

    /// After the broadcaster's LiveKit participant disconnects while the viewer is still connected.
    /// For OBS, the host may disconnect while the program feed (ingress) stays live — do not end watch.
    static func shouldEndWatchFromBroadcasterDisconnect(
        isWatching: Bool,
        isVoluntaryLeave: Bool,
        disconnectedIdentity: String?,
        broadcasterIdentity: String?,
        broadcastSourceIsObs: Bool
    ) -> Bool {
        guard isWatching, !isVoluntaryLeave else { return false }
        guard let disconnectedIdentity, let broadcasterIdentity else { return false }
        if broadcastSourceIsObs, disconnectedIdentity == broadcasterIdentity {
            return false
        }
        return disconnectedIdentity == broadcasterIdentity
    }

    /// LiveKit connection dropped — wait for reconnect; do not treat as ended by itself.
    static func shouldDeferStreamEndForConnectionState(_ state: ConnectionState) -> Bool {
        switch state {
        case .connecting, .reconnecting:
            return true
        case .connected, .disconnected, .disconnecting:
            return false
        @unknown default:
            return true
        }
    }

    /// When offline, allow a single successful not-live poll to finish the session (pairs with status polling).
    static func shouldEndWatchFromStatusPollWhileDisconnected(
        isWatching: Bool,
        watchRoomID: RoomID?,
        polledRoomID: RoomID,
        responseLive: Bool,
        pollSucceeded: Bool,
        connectionState: ConnectionState,
        consecutiveSuccessfulNotLivePolls: Int
    ) -> Bool {
        guard pollSucceeded, isWatching else { return false }
        guard watchRoomID == polledRoomID else { return false }
        if responseLive { return false }
        guard connectionState == .disconnected || connectionState == .disconnecting else { return false }
        return consecutiveSuccessfulNotLivePolls >= 1
    }

    static func shouldPresentStreamEndedPopup(
        isVoluntaryLeave: Bool,
        alreadyPresentedForSessionId: String?,
        sessionId: String
    ) -> Bool {
        guard !isVoluntaryLeave else { return false }
        return alreadyPresentedForSessionId != sessionId
    }

    static func nextConsecutiveNotLivePollCount(
        pollSucceeded: Bool,
        responseLive: Bool,
        previousCount: Int
    ) -> Int {
        guard pollSucceeded else { return previousCount }
        return responseLive ? 0 : previousCount + 1
    }
}

struct BroadcastStreamEndedNotice: Identifiable, Equatable, Sendable {
    var id: String { sessionId }
    let sessionId: String
    let roomTitle: String
}

/// LiveKit dropped while the broadcast may still be live (network); viewer can retry watch.
struct BroadcastStreamConnectionLostNotice: Identifiable, Equatable, Sendable {
    var id: String { sessionId }
    let roomID: RoomID
    let sessionId: String
    let roomTitle: String
}

/// Shown when the viewer is kicked from the live stream (still live for others).
struct BroadcastStreamRemovalNotice: Identifiable, Equatable, Sendable {
    var id: String { "\(sessionId)-\(blocked ? "blocked" : "removed")" }
    let sessionId: String
    let roomTitle: String
    /// True when the viewer was blocked and cannot rejoin this session.
    let blocked: Bool
}

struct BroadcastSpeakInviteNotice: Identifiable, Equatable, Sendable {
    var id: String { "\(sessionId)-\(invitationId ?? "grant")" }
    let sessionId: String
    let roomID: RoomID
    let invitationId: String?
    let roomTitle: String
}
