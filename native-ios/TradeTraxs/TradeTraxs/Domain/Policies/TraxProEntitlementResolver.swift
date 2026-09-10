import Foundation

/// Unified TraxPro entitlement — mirrors web ``lib/traxProEntitlement.ts`` / ``isProActive``.
nonisolated enum TraxProEntitlementSource: String, Hashable, Codable, Sendable {
    case none
    case stripe
    case apple
    case manual
    case creator
    case earlyAccess
}

nonisolated struct TraxProEntitlementInputs: Hashable, Sendable {
    var isProFlag: Bool
    var creatorAccess: Bool
    var subscriptionStatus: String?
    var trialEndsAt: Date?
    var earlyAccessStatus: String?
    var earlyAccessCampaignID: String?
    var earlyAccessEnrollmentSource: String?
    var earlyAccessEnrolledAt: Date?
    var earlyAccessStartedAt: Date?
    var earlyAccessEndsAt: Date?
    var appleSubscriptionStatus: String?
    var appleExpiresAt: Date?
    var appleRevokedAt: Date?
}

nonisolated struct TraxProEntitlementResolution: Hashable, Sendable {
    var isActive: Bool
    var source: TraxProEntitlementSource
}

nonisolated enum TraxProEntitlementResolver {
    static func resolve(
        _ inputs: TraxProEntitlementInputs,
        now: Date = Date()
    ) -> TraxProEntitlementResolution {
        if inputs.creatorAccess {
            return TraxProEntitlementResolution(isActive: true, source: .creator)
        }

        if inputs.isProFlag {
            return TraxProEntitlementResolution(isActive: true, source: .manual)
        }

        if isEarlyAccessActive(inputs, now: now) {
            return TraxProEntitlementResolution(isActive: true, source: .earlyAccess)
        }

        if isStripeLikeActive(inputs, now: now) {
            return TraxProEntitlementResolution(isActive: true, source: .stripe)
        }

        if isAppleSubscriptionActive(inputs, now: now) {
            return TraxProEntitlementResolution(isActive: true, source: .apple)
        }

        return TraxProEntitlementResolution(isActive: false, source: .none)
    }

    static func resolve(_ status: BillingStatus, now: Date = Date()) -> TraxProEntitlementResolution {
        resolve(
            TraxProEntitlementInputs(
                isProFlag: status.plan == .pro,
                creatorAccess: status.creatorAccess,
                subscriptionStatus: status.subscriptionStatusRaw,
                trialEndsAt: status.trialEndsAt,
                earlyAccessStatus: status.earlyAccessStatus,
                earlyAccessCampaignID: status.earlyAccessCampaignID,
                earlyAccessEnrollmentSource: status.earlyAccessEnrollmentSource,
                earlyAccessEnrolledAt: status.earlyAccessEnrolledAt,
                earlyAccessStartedAt: status.earlyAccessStartedAt,
                earlyAccessEndsAt: status.earlyAccessEndsAt,
                appleSubscriptionStatus: status.appleSubscriptionStatus,
                appleExpiresAt: status.appleExpiresAt,
                appleRevokedAt: status.appleRevokedAt
            ),
            now: now
        )
    }

    private static func isStripeLikeActive(
        _ inputs: TraxProEntitlementInputs,
        now: Date
    ) -> Bool {
        let status = inputs.subscriptionStatus?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if status == "active" || status == "trialing" || status == "pro" || status == "trial" {
            return true
        }
        if let trialEndsAt = inputs.trialEndsAt, trialEndsAt > now {
            return true
        }
        return false
    }

    private static func isEarlyAccessActive(
        _ inputs: TraxProEntitlementInputs,
        now: Date
    ) -> Bool {
        guard inputs.earlyAccessStatus == "active",
              inputs.earlyAccessCampaignID == "traxs_pro_for_life_v1",
              inputs.earlyAccessEnrollmentSource == "standard_email"
                || inputs.earlyAccessEnrollmentSource == "standard_oauth",
              inputs.earlyAccessEnrolledAt != nil,
              inputs.earlyAccessStartedAt != nil,
              let endsAt = inputs.earlyAccessEndsAt
        else {
            return false
        }
        return endsAt > now
    }

    private static func isAppleSubscriptionActive(
        _ inputs: TraxProEntitlementInputs,
        now: Date
    ) -> Bool {
        if inputs.appleRevokedAt != nil { return false }
        guard let status = inputs.appleSubscriptionStatus?.lowercased() else { return false }
        guard ["active", "grace_period", "billing_retry"].contains(status) else { return false }
        if let expiresAt = inputs.appleExpiresAt {
            return expiresAt > now
        }
        return true
    }
}

