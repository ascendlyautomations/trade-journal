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

    private static func seedCanonicalSample(profileID: ProfileID, detailCache: DetailPresentationCache) {
        let trades = DemoCanonicalDataset.trades()
        let accounts = DemoCanonicalDataset.accounts(owner: profileID)
        DemoCanonicalDataset.seedDetailCache(detailCache, viewer: profileID)
        SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: detailCache)
        SessionOwnerTradesStore.shared.seed(
            trades,
            for: profileID,
            detailCache: detailCache,
            historyComplete: true,
            totalTradeCount: trades.count
        )
        TradingRulesCompliancePreferencesCache.store(
            DemoCanonicalDataset.previewPreferenceContext(for: profileID),
            for: profileID
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