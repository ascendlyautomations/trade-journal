import Foundation

/// Confirmed TraxsPro access for client gating, backed by ``/api/billing/entitlement`` snapshots.
enum TraxProClientAccess: Equatable, Sendable {
    /// Monetization enforcement is off, or Demo Mode is exploring the app.
    case unrestricted
    case pro
    case free
    /// Snapshot missing, stale past offline grace, or entitlement refresh has not completed.
    case unknown
}

/// Single entry point for native Pro vs Free vs unknown access decisions.
@MainActor
enum TraxProEffectiveEntitlement {
    static func clientAccess(
        profileID: ProfileID?,
        demoModeActive: Bool,
        enforcementEnabled: Bool = IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled
    ) -> TraxProClientAccess {
        if demoModeActive || !enforcementEnabled {
            return .unrestricted
        }
        guard let profileID else { return .unknown }
        switch resolvedSnapshotDecision(profileID: profileID) {
        case .grant:
            return .pro
        case .deny:
            return .free
        case .unavailable:
            return .unknown
        }
    }

    static func hasVerifiedTraxProAccess(profileID: ProfileID?) -> Bool {
        switch clientAccess(profileID: profileID, demoModeActive: ExploreModeSupport.isActive) {
        case .pro, .unrestricted:
            return true
        case .free, .unknown:
            return false
        }
    }

    static func shouldRestrictPremiumFeatures(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        clientAccess(profileID: profileID, demoModeActive: demoModeActive) == .free
    }

    static func shouldShowEntitlementVerification(
        demoModeActive: Bool,
        profileID: ProfileID?
    ) -> Bool {
        clientAccess(profileID: profileID, demoModeActive: demoModeActive) == .unknown
    }

    static func snapshotRecord(for profileID: ProfileID) -> EntitlementSnapshotRecord? {
        if let status = SessionBillingEntitlementStore.shared.status,
           status.profileID == profileID,
           status.serverTraxProActive != nil {
            return EntitlementSnapshotRecord(
                userID: profileID.rawValue,
                traxProActive: status.serverTraxProActive == true,
                source: status.entitlementSource.rawValue,
                accessExpiresAt: status.accessExpiresAt,
                revokedAt: status.appleRevokedAt,
                fetchedAt: status.entitlementFetchedAt ?? Date()
            )
        }
        return PersistedEntitlementSnapshotStore.load(userID: profileID.rawValue)
    }

    private static func resolvedSnapshotDecision(profileID: ProfileID) -> EntitlementCacheDecision {
        EntitlementSnapshotPolicy.decision(snapshotRecord(for: profileID))
    }
}