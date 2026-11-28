import SwiftUI

@MainActor
enum TradingRulesAnalyticsPreviewSupport {
    private(set) static var ephemeralSampleActive = false

    static var showsSampleDataChrome: Bool {
        TraxsProPreviewSession.shared.isAnyPreviewActive || ephemeralSampleActive
    }

    /// Bundled demo trades/preferences — TraxsPro preview containers or test-only ephemeral flag.
    static func usesBundledSampleDataPlane(detailCache: DetailPresentationCache) -> Bool {
        if TradingRulesCompliancePresentationStores.isPreviewDetailCache(detailCache) {
            return true
        }
        return ephemeralSampleActive
    }

    /// Free-tier rules analytics chrome on the live Home stack — does not seed production session stores.
    static func beginEphemeralSampleIfNeeded(profileID: ProfileID, detailCache: DetailPresentationCache) {
        _ = (profileID, detailCache)
        guard !TraxsProPreviewSession.shared.isAnyPreviewActive else { return }
        ephemeralSampleActive = true
    }

    static func endEphemeralSampleIfNeeded(profileID: ProfileID?, detailCache: DetailPresentationCache) {
        _ = (profileID, detailCache)
        ephemeralSampleActive = false
    }

    static func allowsTradeDetailNavigation(tradeID: TradeID) -> Bool {
        if !showsSampleDataChrome { return true }
        return TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: tradeID)
    }

    static func resolvedPreferenceContext(for profileID: ProfileID) -> PreferenceRuleContext {
        if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
           preview.viewer == profileID
        {
            return preview.preferenceContext
        }
        return DemoCanonicalDataset.previewPreferenceContext(for: profileID)
    }

    /// TraxsPro / bundled sample plane only — never production `SessionAccountsStore` (IDs won’t match demo trades).
    static func previewAccounts(profileID: ProfileID, detailCache: DetailPresentationCache) -> [TradingAccount] {
        previewAccounts(
            profileID: profileID,
            dependencies: TradingRulesComplianceLoadDependencies(
                detailCache: detailCache,
                tradesRepository: DemoTradeRepository(
                    ownerID: profileID,
                    trades: previewOwnerTrades(profileID: profileID),
                    accounts: DemoCanonicalDataset.accounts(owner: profileID)
                )
            )
        )
    }

    static func previewAccounts(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies
    ) -> [TradingAccount] {
        if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
           preview.viewer == profileID,
           !preview.accounts.isEmpty
        {
            return preview.accounts
        }
        if TradingRulesCompliancePresentationStores.isPreviewDetailCache(dependencies.detailCache),
           let seeded = dependencies.detailCache.accounts(for: profileID),
           !seeded.isEmpty
        {
            return seeded
        }
        return DemoCanonicalDataset.accounts(owner: profileID)
    }

    static func previewOwnerTrades(profileID: ProfileID) -> [Trade] {
        if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
           preview.viewer == profileID
        {
            return preview.trades.filter { $0.mode != .backtest }
        }
        return DemoCanonicalDataset.trades().filter { $0.mode != .backtest }
    }

    static var usesUnrestrictedPreviewRuleFamilies: Bool {
        TraxsProPreviewSession.shared.isAnyPreviewActive
    }

    /// Fixed 1Y / all-accounts scope for bundled sample analytics.
    static func sampleClientScopeFilter(accounts: [TradingAccount]) -> DashboardClientScopeFilter {
        DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .oneYear,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false,
            linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        )
    }

    /// Synchronous bundled rules analytics — same data plane as Dashboard / Reports TraxsPro preview.
    @discardableResult
    static func publishBundledSampleSnapshotSynchronously(
        profileID: ProfileID,
        presentationStore: TradingRulesComplianceSessionStore,
        preferenceContext: PreferenceRuleContext,
        accounts: [TradingAccount],
        ownerTrades: [Trade],
        generation: UInt64,
        dashboardScopeFilter: DashboardClientScopeFilter? = nil
    ) -> Bool {
        guard showsSampleDataChrome else { return false }
        guard !accounts.isEmpty else { return false }

        let filter = dashboardScopeFilter ?? sampleClientScopeFilter(accounts: accounts)
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            filter: filter,
            profileID: profileID,
            accounts: accounts
        )
        let scoped = PsychologyAnalyticsTradeScope.complianceScopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: filter
        )
        guard TradingRulesPlanTier.hasConfiguredRules(context: preferenceContext, isFreeTier: false),
              !scoped.isEmpty
        else { return false }

        let prepared = TradingRulesComplianceDisciplineContextBuilder.prepare(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scopeFilter: filter,
            preferences: preferenceContext,
            historyComplete: true
        )
        let payload = TradingRulesComplianceCompute.computeScopedSync(
            trades: scoped,
            context: preferenceContext,
            dashboardInsights: nil,
            preferDashboardInsightsCache: false,
            discipline: prepared.discipline,
            allowedRuleIDs: nil
        )
        let output = TradingRulesComplianceSnapshotBuilder.outputFromComputedPayload(
            payload: payload,
            preferences: preferenceContext,
            scopedTradeCount: scoped.count,
            ownerTradeCount: prepared.ownerTradeCount,
            historyComplete: true,
            isAuthoritative: true
        )
        presentationStore.publish(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: true,
            inputFingerprint: nil,
            generation: generation
        )
        TradingRulesCompliancePreferencesCache.store(preferenceContext, for: profileID)
        return output.result != nil
    }

    /// Seeds the active TraxsPro preview environment rules store before first paint.
    static func seedActivePreviewEnvironmentRulesPresentation() {
        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else { return }
        let eligible = preview.trades.filter { $0.mode != .backtest }
        _ = publishBundledSampleSnapshotSynchronously(
            profileID: preview.viewer,
            presentationStore: preview.rulesPresentationStore,
            preferenceContext: preview.preferenceContext,
            accounts: preview.accounts,
            ownerTrades: eligible,
            generation: preview.generation
        )
    }

    /// Builds compliance from preview-environment demo trades + preferences only.
    @discardableResult
    static func publishBundledSampleSnapshot(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies,
        preferenceContext: PreferenceRuleContext,
        dashboardScopeFilter: DashboardClientScopeFilter? = nil
    ) async -> Bool {
        guard let store = TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore else {
            return false
        }
        return await publishBundledSampleSnapshot(
            profileID: profileID,
            dependencies: dependencies,
            preferenceContext: preferenceContext,
            presentationStore: store,
            dashboardScopeFilter: dashboardScopeFilter
        )
    }

    @discardableResult
    static func publishBundledSampleSnapshot(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies,
        preferenceContext: PreferenceRuleContext,
        presentationStore: TradingRulesComplianceSessionStore,
        dashboardScopeFilter: DashboardClientScopeFilter? = nil
    ) async -> Bool {
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot enter profileID=\(profileID.rawValue) showsSampleDataChrome=\(showsSampleDataChrome)"
        )
        guard showsSampleDataChrome else {
            RulesPreviewDebugLog.log("publishBundledSampleSnapshot guard fail: showsSampleDataChrome=false")
            return false
        }
        guard presentationStore === TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore
        else {
            RulesPreviewDebugLog.log(
                "publishBundledSampleSnapshot guard fail: presentationStore not env rules store got=\(RulesPreviewDebugLog.storeID(presentationStore))"
            )
            return false
        }
        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
              preview.viewer == profileID
        else {
            RulesPreviewDebugLog.log(
                "publishBundledSampleSnapshot guard fail: previewEnvironment missing or viewer mismatch env=\(RulesPreviewDebugLog.describe(TraxsProPreviewSession.shared.activePreviewEnvironment))"
            )
            return false
        }
        let generation = preview.generation
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot active env \(RulesPreviewDebugLog.describe(preview)) \(RulesPreviewDebugLog.describeConfiguredRules(context: preferenceContext))"
        )

        let accounts = preview.accounts
        guard !accounts.isEmpty else {
            RulesPreviewDebugLog.log("publishBundledSampleSnapshot guard fail: preview.accounts empty")
            return false
        }

        let filter = dashboardScopeFilter ?? sampleClientScopeFilter(accounts: accounts)
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot inputs trades=\(preview.trades.count) accounts=\(accounts.count) \(RulesPreviewDebugLog.describe(scopeFilter: filter))"
        )
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            filter: filter,
            profileID: profileID,
            accounts: accounts
        )
        let output = await TradingRulesComplianceSnapshotBuilder.build(
            profileID: profileID,
            scope: scope,
            accounts: accounts,
            dependencies: dependencies,
            injectedPreferences: preferenceContext,
            dashboardInsights: nil
        )
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot builder \(RulesPreviewDebugLog.describe(output: output)) \(RulesPreviewDebugLog.describe(scope: scope))"
        )
        guard let active = TraxsProPreviewSession.shared.activePreviewEnvironment,
              active.viewer == profileID,
              active.isCurrentGeneration(generation)
        else {
            RulesPreviewDebugLog.log(
                "publishBundledSampleSnapshot guard fail: stale generation wanted=\(generation) env=\(RulesPreviewDebugLog.describe(TraxsProPreviewSession.shared.activePreviewEnvironment))"
            )
            return false
        }
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot publishing to store=\(RulesPreviewDebugLog.storeID(presentationStore)) generation=\(generation)"
        )
        presentationStore.publish(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: true,
            inputFingerprint: nil,
            generation: generation
        )
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot published \(RulesPreviewDebugLog.describe(session: presentationStore))"
        )
        return true
    }
}

struct TradingRulesAnalyticsSampleDataBanner: View {
    var compactListSubtitle: Bool = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
            Text(
                compactListSubtitle
                    ? MonetizationPlanCopy.tradingRulesAnalyticsPreviewListSubtitle
                    : MonetizationPlanCopy.tradingRulesAnalyticsPreviewSampleDataNote
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary)
        .overlay(alignment: .bottom) {
            colors.separator.frame(height: ExperienceBorder.hairline)
        }
        .accessibilityIdentifier("tradingRulesAnalytics.sampleBanner")
    }
}