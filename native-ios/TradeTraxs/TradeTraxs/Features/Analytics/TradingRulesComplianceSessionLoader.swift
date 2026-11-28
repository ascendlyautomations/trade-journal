import Foundation

struct TradingRulesComplianceLoadDependencies {
    let detailCache: DetailPresentationCache
    let tradesRepository: any TradeRepository
    var tradingPreferences: (any TradingPreferencesRepository)? = nil
}

enum TradingRulesComplianceLoadOutcome: Equatable {
    case ready
    case failed(String)
}

@MainActor
enum TradingRulesComplianceSessionLoader {
    private static var inFlightProfileID: ProfileID?
    private static var inFlightTask: Task<TradingRulesComplianceLoadOutcome, Never>?

    static func refresh(
        dependencies: TradingRulesComplianceLoadDependencies,
        dashboardViewModel: DashboardViewModel?
    ) async -> TradingRulesComplianceLoadOutcome {
        let presentationStore = TradingRulesCompliancePresentationStores.store(
            detailCache: dependencies.detailCache
        )
        guard let profileID = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) })
        else {
            presentationStore.reset()
            return .failed("Sign in to view trading rules analytics.")
        }

        presentationStore.clearIfProfileMismatch(profileID)

        if let dashboardViewModel,
           dashboardViewModel.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            await dashboardViewModel.ensureTradingRulesComplianceForPresentation(
                dependencies: dependencies
            )
            if let message = presentationStore.loadError {
                return .failed(message)
            }
            if presentationStore.insufficientScope {
                return .ready
            }
            return .ready
        }

        if let inFlightTask, inFlightProfileID == profileID {
            return await inFlightTask.value
        }

        let task = Task { () -> TradingRulesComplianceLoadOutcome in
            await performColdRefresh(
                dependencies: dependencies,
                profileID: profileID,
                presentationStore: presentationStore
            )
        }
        inFlightProfileID = profileID
        inFlightTask = task
        defer {
            inFlightTask = nil
            inFlightProfileID = nil
        }
        return await task.value
    }

    static func revealCachedSnapshotIfPossible(
        profileID: ProfileID,
        detailCache: DetailPresentationCache,
        dashboardViewModel: DashboardViewModel? = nil
    ) -> Bool {
        let presentationStore = TradingRulesCompliancePresentationStores.store(detailCache: detailCache)
        presentationStore.clearIfProfileMismatch(profileID)
        let accounts: [TradingAccount] = TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome
            ? TradingRulesAnalyticsPreviewSupport.previewAccounts(profileID: profileID, detailCache: detailCache)
            : (SessionAccountsStore.shared.cached(for: profileID) ?? [])
        let linked = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        let scope: PsychologyAnalyticsScopeResolver.Resolved
        if let dashboardViewModel,
           dashboardViewModel.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            var filter = dashboardViewModel.clientScopeFilter()
            filter.linkedAccountModes = linked
            scope = PsychologyAnalyticsScopeResolver.resolve(
                filter: filter,
                profileID: profileID,
                accounts: accounts
            )
        } else {
            scope = PsychologyAnalyticsScopeResolver.resolve(
                profileID: profileID,
                linkedAccountModes: linked
            )
        }
        guard presentationStore.matchesCachedPresentation(
            profileID: profileID,
            scopeFingerprint: scope.fingerprint
        ), presentationStore.ready
        else {
            return false
        }
        return !presentationStore.insufficientScope
            || presentationStore.scopedTradeCount > 0
    }

    private static func performColdRefresh(
        dependencies: TradingRulesComplianceLoadDependencies,
        profileID: ProfileID,
        presentationStore: TradingRulesComplianceSessionStore
    ) async -> TradingRulesComplianceLoadOutcome {
        let usesBundledSample = TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome
        if usesBundledSample,
           presentationStore.ready,
           presentationStore.profileID == profileID,
           presentationStore.result != nil
        {
            RulesPreviewDebugLog.log(
                "SessionLoader.performColdRefresh skip — populated preview snapshot retained \(RulesPreviewDebugLog.describe(session: presentationStore))"
            )
            return .ready
        }
        if !usesBundledSample {
            await SessionNetworkGate.shared.awaitReady()
        }

        var accounts = await loadAccounts(profileID: profileID, dependencies: dependencies)
        if usesBundledSample, accounts.isEmpty {
            accounts = DemoCanonicalDataset.accounts(owner: profileID)
        }
        let scope: PsychologyAnalyticsScopeResolver.Resolved
        if usesBundledSample {
            scope = PsychologyAnalyticsScopeResolver.resolve(
                filter: TradingRulesAnalyticsPreviewSupport.sampleClientScopeFilter(accounts: accounts),
                profileID: profileID,
                accounts: accounts
            )
        } else {
            let persisted = PsychologyAnalyticsScopeResolver.resolve(
                profileID: profileID,
                linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
            )
            scope = PsychologyAnalyticsScopeResolver.resolve(
                filter: persisted.filter,
                profileID: profileID,
                accounts: accounts
            )
        }

        let injectedPreferences: PreferenceRuleContext? = usesBundledSample
            ? TradingRulesAnalyticsPreviewSupport.resolvedPreferenceContext(for: profileID)
            : nil

        let baseline = TradingRulesComplianceRecomputeCoordinator.currentGeneration
        let output = await TradingRulesComplianceSnapshotBuilder.build(
            profileID: profileID,
            scope: scope,
            accounts: accounts,
            dependencies: dependencies,
            injectedPreferences: injectedPreferences
        )
        guard TradingRulesComplianceRecomputeCoordinator.isCurrent(baseline) else {
            if presentationStore.ready {
                return .ready
            }
            if let preferencesError = output.preferencesError {
                return .failed(preferencesError)
            }
            return .ready
        }
        if usesBundledSample,
           presentationStore.result != nil,
           output.result == nil,
           output.scopedTradeCount == 0
        {
            RulesPreviewDebugLog.log(
                "SessionLoader.performColdRefresh blocked empty overwrite of populated preview \(RulesPreviewDebugLog.describe(output: output)) kept \(RulesPreviewDebugLog.describe(session: presentationStore))"
            )
            return .ready
        }

        let token = TradingRulesComplianceRecomputeCoordinator.beginPublish()
        let keptExistingRules = !presentationStore.commit(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: true,
            inputFingerprint: nil,
            generation: token,
            preferencesUnavailable: output.preferencesContext == nil || output.preferencesError != nil
        ) && presentationStore.retainsConfiguredRules(for: profileID)
        if keptExistingRules {
            return .ready
        }

        if let preferencesError = output.preferencesError {
            return .failed(preferencesError)
        }
        if let tradesError = output.tradesError, output.scopedTradeCount == 0, output.ownerTradeCount == 0 {
            return .failed(tradesError)
        }
        return .ready
    }

    private static func loadAccounts(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies
    ) async -> [TradingAccount] {
        if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
            let previewAccounts = TradingRulesAnalyticsPreviewSupport.previewAccounts(
                profileID: profileID,
                dependencies: dependencies
            )
            if !previewAccounts.isEmpty {
                RulesPreviewDebugLog.log(
                    "SessionLoader.loadAccounts preview plane accounts=\(previewAccounts.count) profileID=\(profileID.rawValue)"
                )
                return previewAccounts
            }
        }
        if let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            return cached
        }
        if let seeded = dependencies.detailCache.accounts(for: profileID), !seeded.isEmpty {
            return seeded
        }
        do {
            return try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: dependencies.detailCache,
                repository: dependencies.tradesRepository,
                forceNetwork: false,
                viewerProfileID: profileID
            )
        } catch {
            return SessionAccountsStore.shared.cached(for: profileID) ?? []
        }
    }
}
