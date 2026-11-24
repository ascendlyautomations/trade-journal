import Foundation

/// Session-scoped join checks, distinct from room bans and transient network failures.
enum BroadcastViewerJoinAccessGate {
    static func isJoinDenied(
        snapshot: LiveKitBroadcastInteractiveStateResponse.Snapshot,
        activeSessionId: String?,
        viewerUserId: String?
    ) -> Bool {
        if let activeSessionId,
           let snapId = snapshot.sessionId,
           !activeSessionId.isEmpty,
           !snapId.isEmpty,
           snapId != activeSessionId
        {
            return false
        }

        let viewerId = viewerUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if snapshot.blockedFromBroadcastRejoin == true {
            return true
        }
        if !viewerId.isEmpty, snapshot.sessionBlocks?.contains(viewerId) == true {
            return true
        }
        return false
    }
}