import SwiftUI

struct TradingRulesComplianceTrendsView: View {
    @Bindable private var session: TradingRulesComplianceSessionStore

    @Environment(\.themeColors) private var colors

    init(
        detailCache: DetailPresentationCache? = nil,
        sessionStore: TradingRulesComplianceSessionStore? = nil
    ) {
        if let sessionStore {
            _session = Bindable(sessionStore)
        } else if let detailCache {
            _session = Bindable(TradingRulesCompliancePresentationStores.store(detailCache: detailCache))
        } else {
            _session = Bindable(
                TradingRulesCompliancePresentationStores.store(
                    forPreviewUI: TraxsProPreviewSession.shared.activePreviewEnvironment != nil
                )
            )
        }
    }

    private static let trendsInfo = (
        title: "Compliance trends",
        body: "Each bar is compliance % for that week or month: rules followed ÷ evaluable checks in your dashboard scope. Faded bars mean too little data for that period."
    )

    var body: some View {
        Group {
            if let result = session.result {
                scrollContent(result: result)
            } else if session.loadError != nil {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "Couldn't load trends",
                    message: "Return to Trading Rules Analytics and try again."
                )
            } else {
                ExperienceLoadingSpinner(message: "Loading trends…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trading Rules Trends")
        .safeAreaInset(edge: .top, spacing: 0) {
            if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
                TradingRulesAnalyticsSampleDataBanner(compactListSubtitle: true)
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.trends")
    }

    @ViewBuilder
    private func scrollContent(result: TradingRulesComplianceAnalytics.Result) -> some View {
        let progress = result.disciplineProgress
        let dailySeries = progress.historyPoints.map {
            TradingRulesComplianceAnalytics.TrendPoint(
                key: $0.key,
                label: $0.label,
                adherencePercent: $0.adherencePercent,
                evaluated: $0.evaluated,
                followed: 0,
                violations: 0,
                unevaluatedChecks: 0,
                tradeCount: 0,
                insufficientData: $0.insufficientData,
                coverageNote: nil
            )
        }
        let prefersDaily = !dailySeries.isEmpty
            && (dailySeries.count <= 31 || result.weeklyTrend.count <= 2)
        let weeklySeries = prefersDaily ? dailySeries : result.weeklyTrend

        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                if !session.scopeLabel.isEmpty {
                    Text(session.scopeLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }

                AnalyticsSectionHeader(
                    title: "Trends",
                    infoTitle: Self.trendsInfo.title,
                    infoBody: Self.trendsInfo.body,
                    infoAccessibilityID: "tradingRulesAnalytics.trends.info"
                )

                TradingRulesComplianceTrendCharts(
                    weekly: weeklySeries,
                    monthly: result.monthlyTrend,
                    layout: .standard
                )
            }
            .padding(ExperienceSpacing.md)
        }
    }
}