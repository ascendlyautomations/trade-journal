import Foundation

nonisolated struct DefaultBillingRepository: BillingRepository, MonetizationConfigurationRefreshing {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let storeKitSync: (any StoreKitEntitlementSyncing)?
    private let entitlementClient: (any AppleSubscriptionSyncClienting)?

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        storeKitSync: (any StoreKitEntitlementSyncing)? = nil,
        entitlementClient: (any AppleSubscriptionSyncClienting)? = nil
    ) {
        self.supabase = supabase
        self.cache = cache
        self.storeKitSync = storeKitSync
        self.entitlementClient = entitlementClient
    }

    func refreshMonetizationConfiguration(for profileID: ProfileID) async {
        let userID = profileID.rawValue
        await MonetizationConfigRefreshFlight.shared.run(userID: userID) { [self] in
            await self.fetchAndApplyMonetizationConfiguration(for: profileID)
        }
    }

    private func fetchAndApplyMonetizationConfiguration(for profileID: ProfileID) async -> Bool {
        let userID = profileID.rawValue
        MonetizationRuntimeConfiguration.shared.restoreCache(userID: userID)
        guard let entitlementClient else {
            logMonetizationConfig(
                userID: userID,
                globalPaywall: "unknown",
                accountOverride: "unknown",
                effectivePaywall: MonetizationRuntimeConfiguration.shared.iosPaywallEnabled,
                source: "noClient"
            )
            return false
        }
        do {
            let config = try await entitlementClient.fetchMonetizationConfig()
            MonetizationRuntimeConfiguration.shared.applySuccessfulFetch(
                CachedMonetizationFlags(
                    iosPaywallEnabled: config.iosPaywallEnabled,
                    entitlementEnforcementEnabled: config.entitlementEnforcementEnabled
                ),
                userID: userID
            )
            let source = config.settingsPresent == false ? "server settingsMissing" : "server"
            logMonetizationConfig(
                userID: userID,
                globalPaywall: debugFlag(config.globalIosPaywallEnabled),
                accountOverride: debugOverride(config.accountIosPaywallOverride),
                effectivePaywall: config.iosPaywallEnabled,
                source: source
            )
            return true
        } catch {
            // Keep the restored cache, or false when there is no cache.
            logMonetizationConfig(
                userID: userID,
                globalPaywall: "unknown",
                accountOverride: "unknown",
                effectivePaywall: MonetizationRuntimeConfiguration.shared.iosPaywallEnabled,
                source: "fetchFailed \(monetizationConfigFailureLabel(error))"
            )
            return false
        }
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        try await loadServerEntitlement(for: profileID, syncStoreKit: false)
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? {
        let status = try await status(for: profileID)
        guard status.hasTraxProAccess else { return nil }
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
        await refreshMonetizationConfiguration(for: profileID)
        return try await loadServerEntitlement(for: profileID, syncStoreKit: true)
    }

    private func loadServerEntitlement(
        for profileID: ProfileID,
        syncStoreKit: Bool
    ) async throws -> BillingStatus {
        _ = supabase
        _ = cache
        if syncStoreKit,
           IosSubscriptionReleaseConfiguration.iosPaywallEnabled,
           let storeKitSync {
            try? await storeKitSync.syncVerifiedTransactionsToServer()
        }

        if let entitlementClient {
            do {
                let response = try await entitlementClient.fetchEntitlement()
                let status = mapServerEntitlement(response, profileID: profileID)
                PersistedEntitlementSnapshotStore.save(snapshotRecord(from: status))
                return status
            } catch {
                if let cached = statusFromCache(profileID: profileID) {
                    return cached
                }
                throw error
            }
        }

        if let cached = statusFromCache(profileID: profileID) {
            return cached
        }
        throw AppError.unknown(message: "Billing entitlement is unavailable")
    }

    private func statusFromCache(profileID: ProfileID) -> BillingStatus? {
        guard let record = PersistedEntitlementSnapshotStore.load(userID: profileID.rawValue) else {
            return nil
        }
        switch EntitlementSnapshotPolicy.decision(record) {
        case .unavailable:
            return nil
        case .deny:
            return BillingStatus(
                profileID: profileID,
                plan: .free,
                lifecycle: .expired,
                isProEntitled: false,
                serverTraxProActive: false,
                accessExpiresAt: record.accessExpiresAt,
                entitlementFetchedAt: record.fetchedAt
            )
        case .grant:
            var status = BillingStatus(
                profileID: profileID,
                plan: .free,
                lifecycle: .active,
                isProEntitled: false,
                serverTraxProActive: true,
                accessExpiresAt: record.accessExpiresAt,
                entitlementFetchedAt: record.fetchedAt
            )
            status.entitlementSource = mapSource(record.source)
            return applyEnforcementCaps(status)
        }
    }

    private func mapServerEntitlement(
        _ response: BillingEntitlementResponse,
        profileID: ProfileID
    ) -> BillingStatus {
        let source = mapSource(response.source)
        let fetchedAt = response.issuedAt.flatMap(ISO8601.date(from:)) ?? Date()
        var status = BillingStatus(
            profileID: profileID,
            plan: source == .manual || source == .launchAccess ? .pro : .free,
            lifecycle: mapLifecycle(response.subscriptionStatus),
            isProEntitled: false,
            trialEndsAt: response.trialEndsAt.flatMap(ISO8601.date(from:)),
            currentPeriodEndsAt: response.currentPeriodEndsAt.flatMap(ISO8601.date(from:)),
            billingInterval: mapInterval(response.billingInterval),
            cancelAtPeriodEnd: response.cancelAtPeriodEnd == true,
            creatorAccess: source == .creator,
            subscriptionStatusRaw: response.subscriptionStatus,
            appleSubscriptionStatus: response.appleSubscriptionStatus,
            appleExpiresAt: response.appleExpiresAt.flatMap(ISO8601.date(from:)),
            appleRevokedAt: response.appleRevokedAt.flatMap(ISO8601.date(from:)),
            appleProductID: response.appleProductId,
            entitlementSource: response.traxProActive ? source : .none,
            serverTraxProActive: response.traxProActive,
            accessExpiresAt: response.accessExpiresAt.flatMap(ISO8601.date(from:)),
            entitlementFetchedAt: fetchedAt
        )
        if response.traxProActive, status.lifecycle == .none, source == .apple || source == .stripe {
            status.lifecycle = .active
        }
        return applyEnforcementCaps(status)
    }

    private func snapshotRecord(from status: BillingStatus) -> EntitlementSnapshotRecord {
        EntitlementSnapshotRecord(
            userID: status.profileID.rawValue,
            traxProActive: status.serverTraxProActive == true,
            source: status.entitlementSource.rawValue,
            accessExpiresAt: status.accessExpiresAt,
            revokedAt: status.appleRevokedAt,
            fetchedAt: status.entitlementFetchedAt ?? Date()
        )
    }

    private func applyEnforcementCaps(_ status: BillingStatus) -> BillingStatus {
        var status = status
        if IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps, !status.hasTraxProAccess {
            status.dailyTradeLimit = FreeTierPolicy.dailyTradeLimit
            status.dailyPostLimit = FreeTierPolicy.dailyPostLimit
            status.dailyMessageLimit = FreeTierPolicy.dailyDirectMessageLimit
            status.maxTradeEntryAccounts = FreeTierPolicy.maxTradeEntryAccounts
        }
        return status
    }

    private func mapSource(_ raw: String?) -> TraxProEntitlementSource {
        switch raw {
        case "stripe":
            return .stripe
        case "apple":
            return .apple
        case "manual":
            return .manual
        case "creator":
            return .creator
        case "early_access":
            return .earlyAccess
        case "launch_access":
            return .launchAccess
        default:
            return .none
        }
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

    private func logMonetizationConfig(
        userID: String,
        globalPaywall: String,
        accountOverride: String,
        effectivePaywall: Bool,
        source: String
    ) {
        #if DEBUG
        print(
            """
            [MonetizationConfig]
            userID=\(userID)
            globalPaywall=\(globalPaywall)
            accountOverride=\(accountOverride)
            effectivePaywall=\(effectivePaywall)
            source=\(source)
            """
        )
        #endif
    }

    private func debugFlag(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "true" : "false"
    }

    private func debugOverride(_ value: Bool?) -> String {
        guard let value else { return "null" }
        return value ? "true" : "false"
    }

    private func monetizationConfigFailureLabel(_ error: Error) -> String {
        guard let appError = error as? AppError else { return "unavailable" }
        if case .unknown(let message) = appError {
            return message
        }
        return "unavailable"
    }
}
