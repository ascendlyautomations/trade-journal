import Foundation

/// Device-local, per-viewer completion for the one-time first-trade detail coachmark.
enum FirstTradeDetailCoachmarkPersistence {
    private static let keyPrefix = "hasSeenFirstTradeDetailCoachmark."

    static func hasSeen(viewerID: ProfileID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: viewerID))
    }

    static func markSeen(viewerID: ProfileID) {
        UserDefaults.standard.set(true, forKey: key(for: viewerID))
    }

    private static func key(for viewerID: ProfileID) -> String {
        keyPrefix + viewerID.rawValue
    }
}

enum FirstTradeDetailCoachmarkEligibility {
    /// Trade count known before a new create is reconciled into session stores.
    static func priorPersistedTradeCount(for owner: ProfileID) -> Int {
        if let meta = SessionOwnerTradesStore.shared.snapshotMetadata(for: owner),
           meta.totalTradeCount > 0
        {
            return meta.totalTradeCount
        }
        return SessionOwnerTradesStore.shared.cached(for: owner)?.count ?? 0
    }
}
