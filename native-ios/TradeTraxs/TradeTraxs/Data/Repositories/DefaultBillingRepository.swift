import Foundation

nonisolated struct DefaultBillingRepository: BillingRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let storeKitSync: (any StoreKitEntitlementSyncing)?

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        storeKitSync: (any StoreKitEntitlementSyncing)? = nil
    ) {
        self.supabase = supabase
        self.cache = cache
        self.storeKitSync = storeKitSync
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        let profile: BillingProfileDTO = try await supabase.database.selectOne(
            BillingProfileDTO.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(BillingProfileDTO.selectColumns),
                SupabaseQuery.eq("id", profileID.rawValue),
            ]
        )

        let appleRow: AppleSubscriptionDTO? = try? await supabase.database.selectOne(
            AppleSubscriptionDTO.self,
            from: "apple_subscriptions",
            query: [
                SupabaseQuery.select(AppleSubscriptionDTO.selectColumns),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                SupabaseQuery.order("expires_at", ascending: false),
                SupabaseQuery.limit(1),
            ]
        )

        return buildBillingStatus(profileID: profileID, profile: profile, apple: appleRow)
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? {
        let status = try await status(for: profileID)
        guard TraxProEntitlementResolver.resolve(status).isActive else { return nil }
        return Subscription(
            id: SubscriptionID(profileID.rawValue),
            profileID: profileID,
            plan: .pro,
            interval: status.billingInterval,
            lifecycle: status.lifecycle,
            trialEndsAt: status.trialEndsAt,
            renewsAt: status.currentPeriodEndsAt ?? status.appleExpiresAt,
            canceledAt: status.cancelAtPeriodEnd ? status.currentPeriodEndsAt : nil
        )
    }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled, let storeKitSync {
            try? await storeKitSync.syncVerifiedTransactionsToServer()
        }
        return try await status(for: profileID)
    }

    private func buildBillingStatus(
        profileID: ProfileID,
        profile: BillingProfileDTO,
        apple: AppleSubscriptionDTO?
    ) -> BillingStatus {
        let lifecycle = mapLifecycle(profile.subscription_status)
        let interval = mapInterval(profile.billing_interval) ?? mapInterval(apple?.billing_interval)
        let trialEndsAt = profile.trial_end.flatMap(ISO8601.date(from:))
        let isProFlag = profile.is_pro == true

        var status = BillingStatus(
            profileID: profileID,
            plan: isProFlag ? .pro : .free,
            lifecycle: lifecycle,
            isProEntitled: isProFlag && (lifecycle == .active || lifecycle == .trialing),
            dailyTradeLimit: nil,
            dailyPostLimit: nil,
            dailyMessageLimit: nil,
            maxTradeEntryAccounts: nil,
            trialEndsAt: trialEndsAt,
            currentPeriodEndsAt: profile.current_period_end.flatMap(ISO8601.date(from:)),
            billingInterval: interval,
            cancelAtPeriodEnd: profile.cancel_at_period_end == true,
            creatorAccess: profile.creator_access == true,
            subscriptionStatusRaw: profile.subscription_status,
            earlyAccessStatus: profile.early_access_status,
            earlyAccessCampaignID: profile.early_access_campaign_id,
            earlyAccessEnrollmentSource: profile.early_access_enrollment_source,
            earlyAccessEnrolledAt: profile.early_access_enrolled_at.flatMap(ISO8601.date(from:)),
            earlyAccessStartedAt: profile.early_access_started_at.flatMap(ISO8601.date(from:)),
            earlyAccessEndsAt: profile.early_access_ends_at.flatMap(ISO8601.date(from:)),
            appleSubscriptionStatus: apple?.status,
            appleExpiresAt: apple?.expires_at.flatMap(ISO8601.date(from:)),
            appleRevokedAt: apple?.revoked_at.flatMap(ISO8601.date(from:)),
            appleProductID: apple?.product_id
        )

        let resolution = TraxProEntitlementResolver.resolve(status)
        status.entitlementSource = resolution.source
        if IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps, !resolution.isActive {
            status.dailyTradeLimit = FreeTierPolicy.dailyTradeLimit
            status.dailyPostLimit = FreeTierPolicy.dailyPostLimit
            status.dailyMessageLimit = FreeTierPolicy.dailyDirectMessageLimit
            status.maxTradeEntryAccounts = FreeTierPolicy.maxTradeEntryAccounts
        }

        return status
    }

    private func mapLifecycle(_ status: String?) -> SubscriptionLifecycle {
        switch status?.lowercased() {
        case "active", "pro":
            return .active
        case "trialing", "trial":
            return .trialing
        case "past_due":
            return .pastDue
        case "canceled", "cancelled":
            return .canceled
        case "expired":
            return .expired
        default:
            return .none
        }
    }

    private func mapInterval(_ raw: String?) -> BillingInterval? {
        switch raw?.lowercased() {
        case "month", "monthly":
            return .monthly
        case "six_month", "six-month", "6month", "semiannual":
            return .sixMonth
        case "year", "yearly", "annual":
            return .yearly
        default:
            return nil
        }
    }
}

nonisolated struct BillingProfileDTO: Codable, Sendable {
    static let selectColumns =
        "id,is_pro,creator_access,subscription_status,trial_end,current_period_end,billing_interval,cancel_at_period_end,early_access_status,early_access_campaign_id,early_access_enrollment_source,early_access_enrolled_at,early_access_started_at,early_access_ends_at"

    var id: String?
    var is_pro: Bool?
    var creator_access: Bool?
    var subscription_status: String?
    var trial_end: String?
    var current_period_end: String?
    var billing_interval: String?
    var cancel_at_period_end: Bool?
    var early_access_status: String?
    var early_access_campaign_id: String?
    var early_access_enrollment_source: String?
    var early_access_enrolled_at: String?
    var early_access_started_at: String?
    var early_access_ends_at: String?
}

nonisolated struct AppleSubscriptionDTO: Codable, Sendable {
    static let selectColumns =
        "product_id,status,expires_at,revoked_at,billing_interval"

    var product_id: String?
    var status: String?
    var expires_at: String?
    var revoked_at: String?
    var billing_interval: String?
}
