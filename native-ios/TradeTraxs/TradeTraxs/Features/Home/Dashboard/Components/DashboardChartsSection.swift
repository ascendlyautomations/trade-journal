import SwiftUI

/// Full-width analytics charts — Phase 2 visuals + Phase 3 interactions.
///
/// Flow: Win/Loss, sessions, weekdays, direction, hours, R:R, symbols, setups, hold, drawdown.
struct DashboardChartsSection: View {
    let summary: DashboardChartMetrics.Summary
    var onBrowseWins: (() -> Void)?
    var onBrowseLosses: (() -> Void)?
    var onBrowseSession: ((String) -> Void)?
    var onBrowseWeekday: ((String) -> Void)?
    var onBrowseHour: ((String) -> Void)?
    var onBrowseLong: (() -> Void)?
    var onBrowseShort: (() -> Void)?
    var onBrowseHoldBucket: ((String) -> Void)?
    /// When true, hides Drawdown, Hold Time, and Setup Performance only (confirmed Free + monetization gates).
    var hidesPremiumDashboardCharts: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
            chartBlock(title: "Win / Loss", info: DashboardChartInfo.winLoss) {
                DashboardWinLossRingView(
                    winCount: summary.winCount,
                    lossCount: summary.lossCount,
                    onSelectWins: onBrowseWins,
                    onSelectLosses: onBrowseLosses
                )
            }
            chartBlock(title: "Trading Sessions", info: DashboardChartInfo.tradingSessions) {
                DashboardSessionBarsView(
                    performance: summary.sessionPerformance,
                    sessions: summary.sessions,
                    onSelect: onBrowseSession
                )
            }
            chartBlock(title: "Weekdays", info: DashboardChartInfo.weekdays) {
                DashboardWeekdayHeatmapView(
                    points: summary.weekdayHeatmap,
                    onSelect: onBrowseWeekday
                )
            }
            chartBlock(title: "Long vs Short", info: DashboardChartInfo.longVsShort) {
                if let comparison = summary.longShortComparison,
                   comparison.long != nil || comparison.short != nil {
                    DashboardLongShortComparisonView(
                        comparison: comparison,
                        onSelectLong: onBrowseLong,
                        onSelectShort: onBrowseShort
                    )
                } else {
                    DashboardLongShortDonutView(
                        longCount: summary.longTradeCount,
                        shortCount: summary.shortTradeCount,
                        longPnL: summary.longShort.first(where: { $0.label == "Long" })?.value ?? 0,
                        shortPnL: summary.longShort.first(where: { $0.label == "Short" })?.value ?? 0,
                        onSelectLong: onBrowseLong,
                        onSelectShort: onBrowseShort
                    )
                }
            }
            if summary.hourHeatmap.contains(where: { abs($0.value) > 0.01 }) {
                chartBlock(title: "Trading Hours", info: DashboardChartInfo.tradingHours) {
                    DashboardHourTimelineView(
                        points: summary.hourHeatmap,
                        highlights: summary.hourHighlights,
                        onSelect: onBrowseHour
                    )
                }
            }
            chartBlock(title: "R:R Targeting", info: DashboardChartInfo.rrTargeting) {
                DashboardRrTargetAnalysisView(analysis: summary.rrTargetAnalysis)
            }
            if !summary.symbolPerformance.isEmpty {
                chartBlock(title: "Symbol Performance", info: DashboardChartInfo.symbolPerformance) {
                    DashboardSymbolRankedBarsView(rows: summary.symbolPerformance)
                }
            }
            if !hidesPremiumDashboardCharts,
               let strategies = summary.strategyHighlights,
               strategies.best != nil || strategies.worst != nil {
                chartBlock(title: "Setup Performance", info: DashboardChartInfo.setupPerformance) {
                    DashboardStrategyHighlightsView(highlights: strategies)
                }
            }
            if !hidesPremiumDashboardCharts {
                chartBlock(title: "Hold Time", info: DashboardChartInfo.holdTime) {
                    if summary.holdTimeHistogram.isEmpty {
                        DashboardChartEmptyCopy(
                            message: "Your hold time distribution will appear after more completed trades."
                        )
                    } else {
                        DashboardHoldHistogramView(
                            buckets: summary.holdTimeHistogram,
                            averages: summary.holdTime,
                            holdExtremes: summary.holdExtremes,
                            onSelectBucket: onBrowseHoldBucket
                        )
                    }
                }
                chartBlock(title: "Drawdown", info: DashboardChartInfo.drawdown) {
                    DashboardUnderwaterDrawdownView(
                        series: summary.drawdownSeries,
                        maxDrawdown: summary.maxDrawdown
                    )
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.charts")
    }

    private func chartBlock<Content: View>(
        title: String,
        info: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.medium)
                AnalyticsMetricInfoButton(
                    title: title,
                    bodyText: info,
                    accessibilityID: "dashboard.chartInfo.\(DashboardChartInfo.identifier(for: title))"
                )
                Spacer(minLength: 0)
            }
            .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExperienceSpacing.md)
                .experienceDashboardCard(prominence: .standard)
        }
        .accessibilityElement(children: .contain)
    }
}

enum DashboardChartInfo {
    static let winLoss = "Wins are closed trades with realized P&L above zero. Losses are below zero. Breakeven trades are excluded. Win rate is wins divided by wins plus losses."
    static let tradingSessions = "Net realized P&L for trades tagged NY AM, NY Lunch, NY PM, London, Asia, or After. Bar length is the size of that net, and the count is how many trades use the tag."
    static let weekdays = "Net realized P&L by futures trading day. The day rolls at 6 PM Eastern, so an entry at or after 6 PM counts on the next calendar day. Green is a net profit and red is a net loss."
    static let longVsShort = "Long and short trades in this filter. Each side shows trade count, net realized P&L, and win rate among trades with a price. Average R uses realized R when the trade can produce one."
    static let tradingHours = "Net realized P&L by entry hour in Eastern Time. Bar height is the size of that hour’s net. Best and worst are the hours with the highest and lowest net."
    static let rrTargeting = "Only trades with both a target R:R and a max R:R reached. Compares the average target with the average max reached. Attainment above 100% means price passed the target before exit. This is not realized P&L."
    static let symbolPerformance = "Net realized P&L by ticker for trades with a price, ranked from strongest to weakest. Bar length is the size of that net."
    static let setupPerformance = "Strongest and weakest named setups by net realized P&L. A setup needs at least 5 priced trades, and at least two setups must qualify."
    static let holdTime = "Hold is exit minus entry for closed trades. Bars count trades under 5 minutes, 5–15 minutes, 15–60 minutes, 1–4 hours, and over 4 hours. Averages are the mean hold for all closes, winners, and losers. The four extremes are the shortest and longest winning and losing holds, with that trade’s realized P&L."
    static let drawdown = "How far equity fell from its running peak, in closed-trade order. The curve is peak minus equity, drawn below zero. Max drawdown is the deepest drop. Drag to read the depth at one trade."

    static func identifier(for title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: " / ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "")
    }
}
