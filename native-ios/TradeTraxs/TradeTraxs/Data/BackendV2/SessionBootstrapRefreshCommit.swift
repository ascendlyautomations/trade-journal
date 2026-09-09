import Foundation

/// Ensures a single shared session-bootstrap network refresh commits apply/cache writes once.
actor SessionBootstrapRefreshCommit {
    static let shared = SessionBootstrapRefreshCommit()

    private var committedSlotIDs: Set<UUID> = []

    func shouldCommit(slotID: UUID, viewerID: String) -> Bool {
        guard !committedSlotIDs.contains(slotID) else { return false }
        committedSlotIDs.insert(slotID)
        _ = viewerID
        return true
    }

    func reset(viewerID: String? = nil) {
        _ = viewerID
        committedSlotIDs.removeAll()
    }
}

/// Observes authoritative session bootstrap network commits (single owner).
@MainActor
protocol SessionBootstrapRefreshObserving: AnyObject {
    func sessionBootstrapDidCommitNetworkRefresh(_ result: SessionBootstrapLoadResult) async
}
