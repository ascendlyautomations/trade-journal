import Foundation

/// Viewer LiveKit disconnect routing (parity with web `classifyViewerBroadcastDisconnect`).
enum BroadcastViewerDisconnectClassification {
    enum Action: Equatable, Sendable {
        case streamEnded
        case removed(blocked: Bool)
        case connectionLost
    }

    static func classify(
        watchingSessionId: String,
        statusLive: Bool,
        statusSessionId: String?,
        snapshot: LiveKitBroadcastInteractiveStateResponse.Snapshot?,
        viewerUserId: String?
    ) -> Action {
        if !statusLive {
            return .streamEnded
        }
        if let statusSessionId,
           !statusSessionId.isEmpty,
           statusSessionId != watchingSessionId
        {
            return .streamEnded
        }
        guard let snapshot else {
            return .streamEnded
        }

        let viewerId = viewerUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var blocked = snapshot.blockedFromBroadcastRejoin == true
        if !viewerId.isEmpty, snapshot.sessionBlocks?.contains(viewerId) == true {
            blocked = true
        }
        if blocked {
            return .removed(blocked: true)
        }

        if snapshot.presentInLiveKitBroadcastRoom != true {
            return .removed(blocked: false)
        }

        return .connectionLost
    }
}
