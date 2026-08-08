import Foundation

nonisolated struct DefaultBillingRepository: BillingRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select("id,is_pro,subscription_status"),
                SupabaseQuery.eq("id", profileID.rawValue),
            ]
        )
        let isPro = dto.is_pro == true
        let lifecycle = mapLifecycle(dto.subscription_status)
        return BillingStatus(
            profileID: profileID,
            plan: isPro ? .pro : .free,
            lifecycle: lifecycle,
            isProEntitled: isPro && (lifecycle == .active || lifecycle == .trialing),
            dailyTradeLimit: isPro ? nil : 10,
            dailyPostLimit: isPro ? nil : 5,
            dailyMessageLimit: isPro ? nil : 50,
            maxTradeEntryAccounts: isPro ? nil : 3
        )
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? {
        let status = try await status(for: profileID)
        guard status.plan == .pro else { return nil }
        return Subscription(
            id: SubscriptionID(profileID.rawValue),
            profileID: profileID,
            plan: status.plan,
            interval: .monthly,
            lifecycle: status.lifecycle,
            trialEndsAt: nil,
            renewsAt: nil,
            canceledAt: nil
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
}
