import Foundation

nonisolated enum SubscriptionPlan: String, Hashable, Codable, Sendable {
    case free
    case pro
}

nonisolated enum BillingInterval: String, Hashable, Codable, Sendable {
    case monthly
    case sixMonth
    case yearly
}

nonisolated enum SubscriptionLifecycle: String, Hashable, Codable, Sendable {
    case none
    case trialing
    case active
    case pastDue
    case canceled
    case expired
}

nonisolated struct Subscription: Hashable, Codable, Sendable, Identifiable {
    var id: SubscriptionID
    var profileID: ProfileID
    var plan: SubscriptionPlan
    var interval: BillingInterval?
    var lifecycle: SubscriptionLifecycle
    var trialEndsAt: Date?
    var renewsAt: Date?
    var canceledAt: Date?
}

nonisolated struct BillingStatus: Hashable, Codable, Sendable {
    var profileID: ProfileID
    var plan: SubscriptionPlan
    var lifecycle: SubscriptionLifecycle
    /// Legacy Stripe-only flag — prefer ``hasTraxProAccess`` / ``entitlementSource``.
    var isProEntitled: Bool
    var dailyTradeLimit: Int?
    var dailyPostLimit: Int?
    var dailyMessageLimit: Int?
    var maxTradeEntryAccounts: Int?
    var trialEndsAt: Date? = nil
    var currentPeriodEndsAt: Date? = nil
    var billingInterval: BillingInterval? = nil
    var cancelAtPeriodEnd: Bool = false
    var creatorAccess: Bool = false
    var subscriptionStatusRaw: String? = nil
    var earlyAccessStatus: String? = nil
    var earlyAccessCampaignID: String? = nil
    var earlyAccessEnrollmentSource: String? = nil
    var earlyAccessEnrolledAt: Date? = nil
    var earlyAccessStartedAt: Date? = nil
    var earlyAccessEndsAt: Date? = nil
    var appleSubscriptionStatus: String? = nil
    var appleExpiresAt: Date? = nil
    var appleRevokedAt: Date? = nil
    var appleProductID: String? = nil
    var entitlementSource: TraxProEntitlementSource = .none
}
