import SwiftUI

@MainActor
enum TradingRulesAnalyticsPreviewSupport {
    private(set) static var ephemeralSampleActive = false

    static var showsSampleDataChrome: Bool {
        TraxsProPreviewSession.shared.isTradingRulesPreviewActive
            || TraxsProPreviewSession.shared.isDashboardPreviewActive
            || ephemeralSampleActive
    }

    static func allowsTradeDetailNavigation(tradeID: TradeID) -> Bool {
        if !showsSampleDataChrome { return true }
        return TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: tradeID)
    }

    static func beginEphemeralSampleIfNeeded(profileID: ProfileID, detailCache: DetailPresentationCache) {
        guard !TraxsProPreviewSession.shared.isAnyPreviewActive else { return }
        guard !ephemeralSampleActive else { return }
        ephemeralSampleActive = true
        seedCanonicalSample(profileID: profileID, detailCache: detailCache)
    }

    static func endEphemeralSampleIfNeeded(profileID: ProfileID?, detailCache: DetailPresentationCache) {
        guard ephemeralSampleActive else { return }
        ephemeralSampleActive = false
        guard let profileID else { return }
        SessionOwnerTradesStore.shared.invalidate(profileID: profileID)
        TradingRulesCompliancePreferencesCache.invalidate(profileID: profileID)
        TradingRulesComplianceSessionStore.shared.reset()
        for id in DemoCanonicalDataset.trades().map(\.id) {
            detailCache.removeTrade(id: id)
        }
    }

    /// Sample trading rules + journal stores for analytics preview (never persisted to Supabase).
    static func seedJournalAndPreferences(
        profileID: ProfileID,
        detailCache: DetailPresentationCache,
        seedDetailCacheTrades: Bool = true
    ) {
        let trades = DemoCanonicalDataset.trades()
        let accounts = DemoCanonicalDataset.accounts(owner: profileID)
        if seedDetailCacheTrades {
            DemoCanonicalDataset.seedDetailCache(detailCache, viewer: profileID)
        }
        SessionAccountsStore.shared.invalidate(profileID: profileID)
        SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: detailCache, kind: .rest)
        SessionOwnerTradesStore.shared.seed(
            trades,
            for: profileID,
            detailCache: detailCache,
            historyComplete: true,
            totalTradeCount: trades.count
        )
        storeResolvedPreferenceContext(for: profileID)
    }

    /// Returns and caches demo rule preferences for the active preview session.
    @discardableResult
    static func resolvedPreferenceContext(for profileID: ProfileID) -> PreferenceRuleContext {
        if let cached = TradingRulesCompliancePreferencesCache.cachedContext(for: profileID) {
            return cached
        }
        let demo = DemoCanonicalDataset.previewPreferenceContext(for: profileID)
        TradingRulesCompliancePreferencesCache.store(demo, for: profileID)
        return demo
    }

    private static func storeResolvedPreferenceContext(for profileID: ProfileID) {
        _ = resolvedPreferenceContext(for: profileID)
    }

    private static func seedCanonicalSample(profileID: ProfileID, detailCache: DetailPresentationCache) {
        seedJournalAndPreferences(profileID: profileID, detailCache: detailCache)
    }

    /// Fixed 1Y / all-accounts scope for bundled sample analytics (matches ``TradingRulesAnalyticsScopeController/applyTraxsProPreviewScopeDefaults()``).
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

    /// Builds compliance from seeded demo trades + preferences only (no dashboard or network hydration).
    @discardableResult
    static func publishBundledSampleSnapshot(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies
    ) async -> Bool {
        guard showsSampleDataChrome else { return false }
        let accounts = SessionAccountsStore.shared.cached(for: profileID)
            ?? dependencies.detailCache.accounts(for: profileID)
            ?? []
        guard !accounts.isEmpty else { return false }

        let scope = PsychologyAnalyticsScopeResolver.resolve(
            filter: sampleClientScopeFilter(accounts: accounts),
            profileID: profileID,
            accounts: accounts
        )
        let injected = resolvedPreferenceContext(for: profileID)
        let output = await TradingRulesComplianceSnapshotBuilder.build(
            profileID: profileID,
            scope: scope,
            accounts: accounts,
            dependencies: dependencies,
            injectedPreferences: injected,
            dashboardInsights: nil
        )
        let token = TradingRulesComplianceRecomputeCoordinator.beginPublish()
        return TradingRulesComplianceSessionStore.shared.commit(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: true,
            inputFingerprint: nil,
            generation: token,
            preferencesUnavailable: false
        )
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