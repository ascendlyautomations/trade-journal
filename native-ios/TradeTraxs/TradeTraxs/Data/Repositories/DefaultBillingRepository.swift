import Foundation

nonisolated struct DefaultBillingRepository: BillingRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        let dto: BillingProfileDTO = try await supabase.database.selectOne(
            BillingProfileDTO.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(
                    "id,is_pro,subscription_status,trial_end,current_period_end,billing_interval,cancel_at_period_end"
                ),
                SupabaseQuery.eq("id", profileID.rawValue),
            ]
        )
        let isPro = dto.is_pro == true
        let lifecycle = mapLifecycle(dto.subscription_status)
        let interval = mapInterval(dto.billing_interval)
        return BillingStatus(
            profileID: profileID,
            plan: isPro ? .pro : .free,
            lifecycle: lifecycle,
            isProEntitled: isPro && (lifecycle == .active || lifecycle == .trialing),
            dailyTradeLimit: isPro ? nil : 10,
            dailyPostLimit: isPro ? nil : 5,
            dailyMessageLimit: isPro ? nil : 50,
            maxTradeEntryAccounts: isPro ? nil : 3,
            trialEndsAt: dto.trial_end.flatMap(ISO8601.date(from:)),
            currentPeriodEndsAt: dto.current_period_end.flatMap(ISO8601.date(from:)),
            billingInterval: interval,
            cancelAtPeriodEnd: dto.cancel_at_period_end == true
        )
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? {
        let status = try await status(for: profileID)
        guard status.plan == .pro || status.lifecycle == .trialing else { return nil }
        return Subscription(
            id: SubscriptionID(profileID.rawValue),
            profileID: profileID,
            plan: status.plan,
            interval: status.billingInterval,
            lifecycle: status.lifecycle,
            trialEndsAt: status.trialEndsAt,
            renewsAt: status.currentPeriodEndsAt,
            canceledAt: status.cancelAtPeriodEnd ? status.currentPeriodEndsAt : nil
        )
    }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        try await status(for: profileID)
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
    var id: String?
    var is_pro: Bool?
    var subscription_status: String?
    var trial_end: String?
    var current_period_end: String?
    var billing_interval: String?
    var cancel_at_period_end: Bool?
}
