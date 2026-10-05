import Foundation

nonisolated enum ProfileAnalyticsOwnerInvalidation {
    static func invalidateOwnerSnapshot(viewerID: ProfileID) {
        guard BackendV2FeatureFlags.isEnabled(.profileAnalyticsGRDB) else { return }
        Task {
            let viewer = viewerID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try? await AnalyticsLocalStore.sharedStore().deleteProfileAnalyticsSnapshots(
                viewerID: viewer,
                subjectProfileID: viewer
            )
        }
    }

    static func submitTradeMutation(old: Trade?, new: Trade?) {
        guard affectsOwnerJournalHeaderMetrics(old: old, new: new) else { return }
        let owner = new?.ownerProfileID ?? old?.ownerProfileID
        guard let owner else { return }
        invalidateOwnerSnapshot(viewerID: owner)
    }

    /// Owner header + analytics — any journal change that can alter Trades / Win % / Profit Factor.
    static func affectsOwnerJournalHeaderMetrics(old: Trade?, new: Trade?) -> Bool {
        switch (old, new) {
        case (nil, _?):
            return true
        case (_?, nil):
            return true
        case (let before?, let after?):
            if before.visibility != after.visibility { return true }
            if before.realizedPnL?.amount != after.realizedPnL?.amount { return true }
            if before.riskReward != after.riskReward { return true }
            if before.mode != after.mode { return true }
            if before.accountMode != after.accountMode { return true }
            if before.accountID != after.accountID { return true }
            if before.entryAt != after.entryAt { return true }
            if before.exitAt != after.exitAt { return true }
            return false
        default:
            return false
        }
    }

    /// Legacy name — tests and GRDB shadow paths.
    static func affectsPublicProfileAnalytics(old: Trade?, new: Trade?) -> Bool {
        affectsOwnerJournalHeaderMetrics(old: old, new: new)
    }
}
