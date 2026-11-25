import SwiftUI

struct TradingRulesDayDetailView: View {
    let dayKey: String
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache

    @Bindable private var session = TradingRulesComplianceSessionStore.shared
    @Environment(\.themeColors) private var colors

    private var dayRow: TradingRulesViolationPatterns.WorstTradingDayRow? {
        session.result?.violationPatterns.worstTradingDays.first { $0.dayKey == dayKey }
    }

    private var violations: [TradingRulesComplianceAnalytics.ViolationEvent] {
        guard let checks = session.result?.complianceChecks else { return [] }
        return TradingRulesViolationPatterns.violations(forDay: dayKey, from: checks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                if !session.scopeLabel.isEmpty {
                    Text(session.scopeLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }

                if let row = dayRow {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text("\(row.violationRatePercent, specifier: "%.1f")%")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                        Text("\(row.violated) violations · \(row.evaluated) evaluated checks")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .experienceTradingRulesCard(prominence: .standard)
                }

                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    Text("Violations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    if violations.isEmpty {
                        Text("No violations recorded for this trading day in scope.")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(violations.enumerated()), id: \.element.id) { index, event in
                                TradingRulesViolationEventRow(
                                    event: event,
                                    onOpenTrade: { tradeID in
                                        guard TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(
                                            tradeID: tradeID
                                        ) else { return }
                                        navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                                    }
                                )
                                if index < violations.count - 1 {
                                    ExperienceDivider()
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                }
            }
            .padding(ExperienceSpacing.md)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(dayRow?.displayDate ?? dayKey)
        .safeAreaInset(edge: .top, spacing: 0) {
            if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
                TradingRulesAnalyticsSampleDataBanner(compactListSubtitle: true)
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.dayDetail")
    }
}
