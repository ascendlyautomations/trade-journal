import Foundation

/// TraxPro access — delegates to ``TraxProEntitlementResolver`` (web `isTraxProActive`).
nonisolated enum TraxProEntitlementPolicy {
    static func isProEntitled(_ status: BillingStatus, now: Date = Date()) -> Bool {
        TraxProEntitlementResolver.resolve(status, now: now).isActive
    }
}

nonisolated extension BillingStatus {
    /// Authoritative TraxPro entitlement. A server snapshot wins over local field math.
    var hasTraxProAccess: Bool {
        if serverTraxProActive != nil {
            let record = EntitlementSnapshotRecord(
                userID: profileID.rawValue,
                traxProActive: serverTraxProActive == true,
                source: entitlementSource.rawValue,
                accessExpiresAt: accessExpiresAt,
                revokedAt: appleRevokedAt,
                fetchedAt: entitlementFetchedAt ?? Date()
            )
            return EntitlementSnapshotPolicy.decision(record) == .grant
        }
        return TraxProEntitlementResolver.resolve(self).isActive
    }
}
