import SwiftUI

enum DashboardEquityCurvePresentation: Equatable {
    case loading
    case compactEmpty
    case chart

    static let emptyTitle = "No equity data"
    static let emptyDetail = "Equity curve displays after 2 trades."
    static let emptyAccessibilityLabel = "No equity data. Equity curve displays after 2 trades."

    /// Loading only while the request is unresolved. A resolved series under two trades collapses.
    static func resolve(tradeCount: Int, isChartLoading: Bool, chartPointCount: Int) -> DashboardEquityCurvePresentation {
        if !isChartLoading && tradeCount < DashboardEquityChartRangeResolver.minimumTradeCountForEquityCurve {
            return .compactEmpty
        }
        if isChartLoading && chartPointCount < DashboardEquityChartRangeResolver.minimumTradeCountForEquityCurve {
            return .loading
        }
        return .chart
    }
}

/// Stocks-style equity centerpiece — period performance first, curve second.
///
/// For one selected account, title/value/curve use tracked account value
/// (starting balance + lifetime realized P&L, prop payout-aware when available).
/// All Accounts keeps cumulative equity. Analytics stay timeframe-based.
struct DashboardEquityHero: View {
    let summary: DashboardChartMetrics.Summary
    let periodTitle: String
    var title: String = "Equity"
    var displayEquity: Decimal
    var chartPoints: [ProfileStatisticsMetrics.EquityPoint]
    var isChartLoading: Bool = false
    var withdrawalSummary: AccountTrackedBalanceSupport.WithdrawalSummary?
    var onWithdrawalSummaryTap: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var numbersReady = false

    init(
        summary: DashboardChartMetrics.Summary,
        periodTitle: String,
        title: String = "Equity",
        displayEquity: Decimal? = nil,
        chartPoints: [ProfileStatisticsMetrics.EquityPoint]? = nil,
        isChartLoading: Bool = false,
        withdrawalSummary: AccountTrackedBalanceSupport.WithdrawalSummary? = nil,
        onWithdrawalSummaryTap: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.periodTitle = periodTitle
        self.title = title
        self.displayEquity = displayEquity ?? summary.currentEquity
        self.chartPoints = chartPoints ?? summary.equityData
        self.isChartLoading = isChartLoading
        self.withdrawalSummary = withdrawalSummary
        self.onWithdrawalSummaryTap = onWithdrawalSummaryTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header
                .padding(.horizontal, ExperienceSpacing.md)

            equityCurve
                .padding(.horizontal, ExperienceSpacing.sm)
        }
        .padding(.bottom, ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
            value: chartPoints.count
        )
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: numbersReady
        )
        .onAppear {
            guard !numbersReady else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                numbersReady = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.equity")
    }

    private var curvePresentation: DashboardEquityCurvePresentation {
        DashboardEquityCurvePresentation.resolve(
            tradeCount: summary.tradeCount,
            isChartLoading: isChartLoading,
            chartPointCount: chartPoints.count
        )
    }

    @ViewBuilder
    private var equityCurve: some View {
        switch curvePresentation {
        case .compactEmpty:
            VStack(spacing: ExperienceSpacing.xxs) {
                Text(DashboardEquityCurvePresentation.emptyTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                Text(DashboardEquityCurvePresentation.emptyDetail)
                    .experienceStyle(.caption2, color: colors.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ExperienceSpacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard.equity.empty")
            .accessibilityLabel(DashboardEquityCurvePresentation.emptyAccessibilityLabel)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .accessibilityIdentifier("dashboard.equity.loading")
                .accessibilityLabel("Loading equity chart")
        case .chart:
            ProfileEquityCurveView(points: chartPoints)
                .frame(height: 280)
                .accessibilityIdentifier("dashboard.equity.chart")
                .accessibilityLabel(title == "Account Value" ? "Account value curve" : "Equity curve")
                .accessibilityHint("Drag to inspect date and \(title.lowercased())")
        }
    }

    private var header: some View {
        ProposedWidthClamp {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Text("·")
                    .experienceStyle(.subheadline, color: colors.tertiaryText)
                Text(periodTitle)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(NumberDisplay.tradeCount(summary.tradeCount))
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .contentTransition(.numericText())
            }

            Text(numbersReady ? DashboardViewModel.money(displayEquity) : "—")
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel("Current \(title.lowercased()) \(DashboardViewModel.money(displayEquity))")

            if numbersReady, let withdrawalSummary {
                withdrawalSummaryLine(withdrawalSummary)
            }

            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                Text(numbersReady ? signedMoney(summary.netPnL) : "—")
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(toneColor(for: summary.netPnL))
                    .contentTransition(.numericText())
                    .accessibilityLabel("Net P and L \(signedMoney(summary.netPnL))")

                Text("Net P&L")
                    .experienceStyle(.footnote, color: colors.secondaryText)

                if numbersReady, let percent = periodChangePercentText {
                    Text(percent)
                        .font(.system(.footnote, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(for: summary.netPnL))
                        .contentTransition(.numericText())
                        .accessibilityLabel("Period change \(percent)")
                }
            }
        }
        }
    }

    /// Presentation-only: % change along the displayed equity series when a non-zero base exists.
    private var periodChangePercentText: String? {
        guard let first = chartPoints.first?.equity,
              let last = chartPoints.last?.equity
        else { return nil }
        let base = abs(NSDecimalNumber(decimal: first).doubleValue)
        guard base > 0.009 else { return nil }
        let delta = NSDecimalNumber(decimal: last - first).doubleValue
        let pct = (delta / base) * 100
        return NumberDisplay.percent(
            pct,
            minimumFractionDigits: 0,
            maximumFractionDigits: abs(pct) >= 10 ? 0 : 1,
            explicitPlus: pct >= 0
        )
    }

    private func signedMoney(_ value: Decimal) -> String {
        NumberDisplay.signedMoney(value)
    }

    private func toneColor(for value: Decimal) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.secondaryText
    }

    @ViewBuilder
    private func withdrawalSummaryLine(
        _ summary: AccountTrackedBalanceSupport.WithdrawalSummary
    ) -> some View {
        let label = summary.compactLabel(formattedTotal: DashboardViewModel.money(summary.totalAmount))
        if let onWithdrawalSummaryTap {
            Button(action: onWithdrawalSummaryTap) {
                Text(label)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint("Opens withdrawal history")
            .accessibilityIdentifier("dashboard.accountValue.withdrawalSummary")
        } else {
            Text(label)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityLabel(label)
        }
    }
}
