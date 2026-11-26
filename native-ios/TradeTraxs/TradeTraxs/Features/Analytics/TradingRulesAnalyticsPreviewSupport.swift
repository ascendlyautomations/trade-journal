import SwiftUI

@MainActor
enum TradingRulesAnalyticsPreviewSupport {
    private(set) static var ephemeralSampleActive = false

    static var showsSampleDataChrome: Bool {
        TraxsProPreviewSession.shared.isAnyPreviewActive || ephemeralSampleActive
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

    /// Builds compliance from preview-environment demo trades + preferences only.
    @discardableResult
    static func publishBundledSampleSnapshot(
        profileID: ProfileID,
        dependencies: TradingRulesComplianceLoadDependencies,
        preferenceContext: PreferenceRuleContext,
        dashboardScopeFilter: DashboardClientScopeFilter? = nil
    ) async -> Bool {
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot enter profileID=\(profileID.rawValue) showsSampleDataChrome=\(showsSampleDataChrome)"
        )
        guard showsSampleDataChrome else {
            RulesPreviewDebugLog.log("publishBundledSampleSnapshot guard fail: showsSampleDataChrome=false")
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
        let presentationStore = TradingRulesCompliancePresentationStores.store(forPreviewUI: true)
        RulesPreviewDebugLog.log(
            "publishBundledSampleSnapshot publishing to store=\(RulesPreviewDebugLog.storeID(presentationStore)) envRulesStore=\(RulesPreviewDebugLog.storeID(active.rulesPresentationStore)) sameInstance=\(presentationStore === active.rulesPresentationStore) generation=\(generation)"
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