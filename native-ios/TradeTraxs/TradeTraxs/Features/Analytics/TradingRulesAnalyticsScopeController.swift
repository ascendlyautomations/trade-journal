import Foundation
import Observation

/// Client scope for Trading Rules Analytics, persisted and synced with Home when the dashboard is bound.
@MainActor
@Observable
final class TradingRulesAnalyticsScopeController {
    private var traxsProPreviewInitialScopeApplied = false
    private(set) var profileID: ProfileID?
    private(set) var accounts: [TradingAccount] = []

    var accountFilter: DashboardAccountFilter = .all
    var dateRange: DashboardDateRange = .thirtyDays
    var customDateInterval: DateInterval?
    var accountTypeFilter: ProfileStatisticsMetrics.Mode = .all
    var showPublicOnly = false
    var hasUserSelectedDateRange = false

    var draftScopeFilters = DashboardScopeFilterDraft.defaults
    var showsFiltersSheet = false
    var showsTimePeriodSheet = false

    private var recomputeTask: Task<Void, Never>?
    private var recomputeGeneration: UInt64 = 0

    var scopeFilterTimeLabel: String {
        DashboardScopeFilterSupport.compactTimeLabel(
            dateRange: dateRange,
            customInterval: customDateInterval
        )
    }

    var showsTimePeriodFilterIndicator: Bool {
        customDateInterval != nil || hasUserSelectedDateRange
    }

    var showsAdvancedFilterIndicator: Bool {
        accountTypeFilter != .all || showPublicOnly
    }

    func hydrate(profileID: ProfileID, accounts: [TradingAccount]) {
        self.profileID = profileID
        self.accounts = accounts
        if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
            if !traxsProPreviewInitialScopeApplied {
                applyTraxsProPreviewScopeDefaults()
                traxsProPreviewInitialScopeApplied = true
            }
            return
        }
        if let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
           dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            importScope(from: dashboard.clientScopeFilter())
        } else {
            loadPersistedScope(profileID: profileID, accounts: accounts)
        }
    }

    /// Fixed 1Y scope for the TraxsPro Trading Rules Analytics sample preview.
    func applyTraxsProPreviewScopeDefaults() {
        accountFilter = .all
        dateRange = .oneYear
        customDateInterval = nil
        accountTypeFilter = .all
        showPublicOnly = false
        hasUserSelectedDateRange = false
    }

    /// Apply preview defaults once per preview session so refresh keeps the user's timeframe.
    func applyTraxsProPreviewScopeDefaultsIfNeeded() {
        guard !traxsProPreviewInitialScopeApplied else { return }
        applyTraxsProPreviewScopeDefaults()
        traxsProPreviewInitialScopeApplied = true
    }

    func resetTraxsProPreviewScopeState() {
        traxsProPreviewInitialScopeApplied = false
    }

    func syncFromDashboardIfAvailable() {
        guard let profileID,
              let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
              dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        else { return }
        importScope(from: dashboard.clientScopeFilter())
    }

    var accountMenuTitle: String {
        OwnerAccountFilterMenuSupport.menuTitle(
            filter: accountFilter,
            accounts: accounts,
            profileID: profileID
        )
    }

    func clientScopeFilter() -> DashboardClientScopeFilter {
        DashboardClientScopeFilter(
            accountFilter: accountFilter,
            dateRange: dateRange,
            customInterval: customDateInterval,
            accountMode: accountTypeFilter,
            showPublicOnly: showPublicOnly,
            linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) }),
            copyTradingGroups: OwnerAccountFilterMenuSupport.copyGroups(for: profileID)
        )
    }

    func resolvedScope(profileID: ProfileID) -> PsychologyAnalyticsScopeResolver.Resolved {
        PsychologyAnalyticsScopeResolver.resolve(
            filter: clientScopeFilter(),
            profileID: profileID,
            accounts: accounts
        )
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        TradingAccountDisplay.ownerDropdownLine(for: account)
    }

    var accountsForMenu: [TradingAccount] {
        let selectedID: TradingAccountID? = {
            if case .account(let id) = accountFilter { return id }
            return nil
        }()
        let resolved = OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: accounts,
            preservingSelection: selectedID
        )
        return DashboardAccountScopePolicy.menuAccounts(
            from: resolved,
            preservingSelection: selectedID
        )
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        let sanitized = OwnerAccountMutationSync.reconciledAccountFilter(
            filter,
            accounts: accounts,
            profileID: profileID
        )
        guard accountFilter != sanitized else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = sanitized
        publishScopeChange()
    }

    func openManageCopyTradingGroups() {
        ExperienceHaptics.play(.selection)
        TradingRulesCompliancePresentationBridge.dashboardViewModel?
            .openManageCopyTradingGroups()
    }

    func handleCopyTradingGroupsMutation() {
        guard let profileID else { return }
        let sanitized = OwnerAccountMutationSync.reconciledAccountFilter(
            accountFilter,
            accounts: accounts,
            profileID: profileID
        )
        guard sanitized != accountFilter else { return }
        accountFilter = sanitized
        publishScopeChange()
    }

    func handleAccountMutation(detailCache: DetailPresentationCache?) {
        guard let profileID else { return }
        guard let loaded = OwnerAccountMutationSync.sessionAccounts(
            profileID: profileID,
            detailCache: detailCache
        ) else { return }
        accounts = loaded
        OwnerAccountMutationSync.seedDetailCacheIfNeeded(loaded, profileID: profileID, detailCache: detailCache)
        let sanitized = OwnerAccountMutationSync.reconciledAccountFilter(
            accountFilter,
            accounts: loaded,
            profileID: profileID
        )
        guard sanitized != accountFilter else { return }
        accountFilter = sanitized
        publishScopeChange()
    }

    func openTimePeriodFilters() {
        ExperienceHaptics.play(.selection)
        prepareDraftScopeFilters()
        showsTimePeriodSheet = true
    }

    func applyTimePeriodFromDraft() {
        ExperienceHaptics.play(.selection)
        let draft = draftScopeFilters
        if draft.timePeriod == .custom {
            let start = draft.customStart ?? Date()
            let end = draft.customEnd ?? start
            customDateInterval = DashboardScopeFilterSupport.normalizedCustomInterval(start: start, end: end)
            hasUserSelectedDateRange = true
        } else {
            customDateInterval = nil
            if let range = draft.timePeriod.dateRange {
                dateRange = range
                hasUserSelectedDateRange = true
            }
        }
        showsTimePeriodSheet = false
        publishScopeChange()
    }

    func applyAdvancedFiltersFromDraft() {
        ExperienceHaptics.play(.selection)
        accountTypeFilter = draftScopeFilters.accountType
        showPublicOnly = draftScopeFilters.visibility == .publicOnly
        showsFiltersSheet = false
        publishScopeChange()
    }

    func prepareDraftScopeFilters() {
        draftScopeFilters = DashboardScopeFilterDraft(
            timePeriod: DashboardTimePeriodPicker(dateRange: dateRange, usesCustomRange: customDateInterval != nil),
            customStart: customDateInterval?.start,
            customEnd: customDateInterval?.end,
            accountType: accountTypeFilter,
            visibility: showPublicOnly ? .publicOnly : .allTrades
        )
    }

    func scheduleRecompute(dependencies: TradingRulesComplianceLoadDependencies) {
        if let profileID,
           let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
           dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            return
        }
        recomputeTask?.cancel()
        recomputeGeneration &+= 1
        let generation = recomputeGeneration
        recomputeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, let self, generation == self.recomputeGeneration else { return }
            await self.performRecompute(dependencies: dependencies, generation: generation)
        }
    }

    func recomputeImmediately(dependencies: TradingRulesComplianceLoadDependencies) async {
        recomputeTask?.cancel()
        recomputeGeneration &+= 1
        let generation = recomputeGeneration
        await performRecompute(dependencies: dependencies, generation: generation)
    }

    private func performRecompute(
        dependencies: TradingRulesComplianceLoadDependencies,
        generation: UInt64
    ) async {
        guard let profileID else { return }
        let usesSampleData = TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome
        if !usesSampleData {
            persistScope(profileID: profileID)
        }

        let scope = resolvedScope(profileID: profileID)
        let injectedPreferences: PreferenceRuleContext? = usesSampleData
            ? TradingRulesAnalyticsPreviewSupport.resolvedPreferenceContext(for: profileID)
            : nil
        let baseline = TradingRulesComplianceRecomputeCoordinator.currentGeneration
        let output = await TradingRulesComplianceSnapshotBuilder.build(
            profileID: profileID,
            scope: scope,
            accounts: accounts,
            dependencies: dependencies,
            injectedPreferences: injectedPreferences,
            dashboardInsights: nil
        )
        guard generation == recomputeGeneration else { return }
        guard TradingRulesComplianceRecomputeCoordinator.isCurrent(baseline) else { return }

        let token = TradingRulesComplianceRecomputeCoordinator.beginPublish()
        let presentationStore = TradingRulesCompliancePresentationStores.store(
            detailCache: dependencies.detailCache
        )
        _ = presentationStore.commit(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: true,
            inputFingerprint: nil,
            generation: token,
            preferencesUnavailable: usesSampleData
                ? false
                : output.preferencesContext == nil || output.preferencesError != nil
        )
    }

    private func publishScopeChange() {
        guard let profileID else { return }
        if !TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
            persistScope(profileID: profileID)
        }
        if let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
           dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            dashboard.applyClientScopeFromAnalytics(clientScopeFilter())
        }
    }

    private func importScope(from filter: DashboardClientScopeFilter) {
        accountFilter = filter.accountFilter
        dateRange = filter.dateRange
        customDateInterval = filter.customInterval
        accountTypeFilter = filter.accountMode
        showPublicOnly = filter.showPublicOnly
    }

    private func loadPersistedScope(profileID: ProfileID, accounts: [TradingAccount]) {
        let resolved = PsychologyAnalyticsScopeResolver.resolve(
            profileID: profileID,
            linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        )
        importScope(from: resolved.filter)
        accountFilter = DashboardAccountScopePolicy.sanitizedFilter(
            resolved.filter.accountFilter,
            accounts: accounts
        )
    }

    private func persistScope(profileID: ProfileID) {
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: dateRange.rawValue,
                customStart: customDateInterval?.start,
                customEnd: customDateInterval?.end,
                accountModeRaw: accountTypeFilter.rawValue,
                showPublicOnly: showPublicOnly,
                hasUserSelectedDateRange: hasUserSelectedDateRange,
                accountFilterKey: DashboardScopeFilterPersistence.accountFilterKey(for: accountFilter)
            )
        )
    }
}