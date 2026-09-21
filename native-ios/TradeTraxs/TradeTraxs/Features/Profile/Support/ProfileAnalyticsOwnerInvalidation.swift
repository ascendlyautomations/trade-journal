import Foundation

nonisolated enum ProfileAnalyticsOwnerInvalidation {
    static func invalidateOwnerSnapshot(viewerID: ProfileID) {
        guard BackendV2FeatureFlags.isEnabled(.profileAnalyticsGRDB) else { return }
        Task {
            let viewer = viewerID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try? await AnalyticsLocalStore().deleteProfileAnalyticsSnapshots(
                viewerID: viewer,
                subjectProfileID: viewer
            )
        }
    }

    static func submitTradeMutation(old: Trade?, new: Trade?) {
        guard affectsPublicProfileAnalytics(old: old, new: new) else { return }
        let owner = new?.ownerProfileID ?? old?.ownerProfileID
        guard let owner else { return }
        invalidateOwnerSnapshot(viewerID: owner)
    }

    static func affectsPublicProfileAnalytics(old: Trade?, new: Trade?) -> Bool {
        func isPublic(_ trade: Trade) -> Bool {
            trade.visibility == .public
        }
        switch (old, new) {
        case (nil, let created?):
            return isPublic(created)
        case (let deleted?, nil):
            return isPublic(deleted)
        case (let before?, let after?):
            if isPublic(before) || isPublic(after) {
                if before.visibility != after.visibility { return true }
                if isPublic(after) {
                    return before.realizedPnL?.amount != after.realizedPnL?.amount
                        || before.entryAt != after.entryAt
                        || before.exitAt != after.exitAt
                        || before.accountID != after.accountID
                        || before.accountMode != after.accountMode
                        || before.mode != after.mode
                }
            }
            return false
        default:
            return false
        }
    }
}
