import Foundation

/// Client-side trade-entry checks. Owned accounts accept trades; ownership is enforced by the repository and Postgres.
@MainActor
enum TradeEntryEntitlementGate {
    enum ViewerTier: Sendable {
        case pro
        case free
    }

    static func viewerTier(profileID: ProfileID) -> ViewerTier {
        if let record = PersistedEntitlementSnapshotStore.load(userID: profileID.rawValue) {
            switch EntitlementSnapshotPolicy.decision(record) {
            case .grant:
                return .pro
            case .deny:
                return .free
            case .unavailable:
                break
            }
        }
        if sessionProfileIndicatesTraxPro(profileID: profileID) {
            return .pro
        }
        return .free
    }

    static func viewerHasTraxProAccess(profileID: ProfileID) -> Bool {
        viewerTier(profileID: profileID) == .pro
    }

    static func accountAllowsNewTrade(_: TradingAccount, viewerTier _: ViewerTier) -> Bool {
        true
    }

    /// Copy-group members are journalable together. `canAddTrades` is not a write gate.
    static func validateAccountsForNewTrades(
        _: [TradingAccount],
        profileID _: ProfileID
    ) -> String? {
        nil
    }

    private static func sessionProfileIndicatesTraxPro(profileID: ProfileID) -> Bool {
        guard let bootstrap = SessionBootstrapStore.shared.last else { return false }
        let session = bootstrap.data.session_profile
        guard session.id == profileID.rawValue || bootstrap.data.viewer.id == profileID.rawValue else {
            return false
        }
        let resolution = TraxProEntitlementResolver.resolve(
            TraxProEntitlementInputs(
                isProFlag: session.is_pro == true,
                creatorAccess: session.creator_access == true,
                subscriptionStatus: session.subscription_status,
                trialEndsAt: session.trial_end.flatMap { ISO8601.date(from: $0) },
                earlyAccessStatus: session.early_access_status,
                earlyAccessCampaignID: session.early_access_campaign_id,
                earlyAccessEnrollmentSource: session.early_access_enrollment_source,
                earlyAccessEnrolledAt: session.early_access_enrolled_at.flatMap { ISO8601.date(from: $0) },
                earlyAccessStartedAt: session.early_access_started_at.flatMap { ISO8601.date(from: $0) },
                earlyAccessEndsAt: session.early_access_ends_at.flatMap { ISO8601.date(from: $0) },
                appleSubscriptionStatus: nil,
                appleExpiresAt: nil,
                appleRevokedAt: nil
            )
        )
        return resolution.isActive
    }
}
