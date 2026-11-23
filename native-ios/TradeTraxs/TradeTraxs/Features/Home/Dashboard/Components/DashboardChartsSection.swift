import SwiftUI

/// Full-width analytics charts — Phase 2 visuals + Phase 3 interactions.
///
/// Flow: Win/Loss … Symbol Performance (Free) → Hold / Hours / R:R / setup / drawdown (TraxsPro subscribers only).
/// Free users see standard charts here; premium charts are summarized in ``DashboardTraxProUpsellSection``.
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
    /// TraxsPro chart blocks — Hold, Hours, R:R, Setup, Drawdown when enforcement is on.
    var premiumChartsPresentation: ProPremiumFeaturePresentation = .unrestricted
    /// When false, only TraxsPro chart blocks render (TraxsPro Dashboard preview).
    var showsStandardCharts: Bool = true
    var onRetryEntitlementVerification: (() -> Void)?
    var entitlementProfileID: ProfileID?

    @Environment(\.themeColors) private var colors

    private var showsTraxsProChartAnalytics: Bool {
        premiumChartsPresentation == .unrestricted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
            if showsStandardCharts {
                standardChartsContent
            }
            traxsProExclusiveChartsBlock
            premiumAdvancedChartsBlock(strategies: summary.strategyHighlights)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.charts")
    }

    @ViewBuilder
    private var standardChartsContent: some View {
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
        if !summary.symbolPerformance.isEmpty {
            chartBlock(title: "Symbol Performance", info: DashboardChartInfo.symbolPerformance) {
                DashboardSymbolRankedBarsView(rows: summary.symbolPerformance)
            }
        }
    }

    @ViewBuilder
    private var traxsProExclusiveChartsBlock: some View {
        if showsTraxsProChartAnalytics {
            holdTimeBlock
            tradingHoursBlock
            rrTargetingBlock
        }
    }

    @ViewBuilder
    private var holdTimeBlock: some View {
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
    }

    @ViewBuilder
    private var tradingHoursBlock: some View {
        let hasHourData = summary.hourHeatmap.contains(where: { abs($0.value) > 0.01 })
        if hasHourData {
            chartBlock(title: "Trading Hours", info: DashboardChartInfo.tradingHours) {
                DashboardHourTimelineView(
                    points: summary.hourHeatmap,
                    highlights: summary.hourHighlights,
                    onSelect: onBrowseHour
                )
            }
        }
    }

    @ViewBuilder
    private var rrTargetingBlock: some View {
        chartBlock(title: "R:R Targeting", info: DashboardChartInfo.rrTargeting) {
            DashboardRrTargetAnalysisView(analysis: summary.rrTargetAnalysis)
        }
    }

    @ViewBuilder
    private func premiumAdvancedChartsBlock(
        strategies: DashboardStrategyHighlights?
    ) -> some View {
        if premiumChartsPresentation == .unrestricted {
            if let strategies,
               strategies.best != nil || strategies.worst != nil {
                chartBlock(title: "Setup Performance", info: DashboardChartInfo.setupPerformance) {
                    DashboardStrategyHighlightsView(highlights: strategies)
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
    static let holdTime = "Hold is exit minus entry for closed trades. Each bucket shows trade count (accent) and average net P&L per trade (green when positive, red when negative; bar height uses dollar magnitude). Ranges: under 5m, 5 to 15m, 15 to 60m, 1 to 4h, and 4h+. Below are mean hold for all closes, winners, and losers, plus fastest and slowest win/loss extremes."
    static let drawdown = "How far equity fell from its running peak, in closed-trade order. The curve is peak minus equity, drawn below zero. Max drawdown is the deepest drop. Drag to read the depth at one trade."

    static func identifier(for title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: " / ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "")
    }
}