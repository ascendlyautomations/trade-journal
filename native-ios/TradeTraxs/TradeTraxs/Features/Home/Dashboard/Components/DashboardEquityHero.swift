import SwiftUI

/// Stocks-style equity centerpiece — period performance first, curve second.
///
/// For a single prop account, title/value/curve use account value
/// (starting balance + realized equity). Analytics stay on realized performance.
struct DashboardEquityHero: View {
    let summary: DashboardChartMetrics.Summary
    let periodTitle: String
    var title: String = "Equity"
    var displayEquity: Decimal
    var chartPoints: [ProfileStatisticsMetrics.EquityPoint]

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var numbersReady = false

    init(
        summary: DashboardChartMetrics.Summary,
        periodTitle: String,
        title: String = "Equity",
        displayEquity: Decimal? = nil,
        chartPoints: [ProfileStatisticsMetrics.EquityPoint]? = nil
    ) {
        self.summary = summary
        self.periodTitle = periodTitle
        self.title = title
        self.displayEquity = displayEquity ?? summary.currentEquity
        self.chartPoints = chartPoints ?? summary.equityData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header
                .padding(.horizontal, ExperienceSpacing.md)

            ProfileEquityCurveView(points: chartPoints)
                .frame(height: 280)
                .padding(.horizontal, ExperienceSpacing.sm)
                .accessibilityLabel(title == "Account Value" ? "Account value curve" : "Equity curve")
                .accessibilityHint("Drag to inspect date and \(title.lowercased())")
        }
        .padding(.top, ExperienceSpacing.sm)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Text("·")
                    .experienceStyle(.subheadline, color: colors.tertiaryText)
                Text(periodTitle)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text("\(summary.tradeCount) trades")
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

    /// Presentation-only: % change along the displayed equity series when a non-zero base exists.
    private var periodChangePercentText: String? {
        guard let first = chartPoints.first?.equity,
              let last = chartPoints.last?.equity
        else { return nil }
        let base = abs(NSDecimalNumber(decimal: first).doubleValue)
        guard base > 0.009 else { return nil }
        let delta = NSDecimalNumber(decimal: last - first).doubleValue
        let pct = (delta / base) * 100
        let formatted = String(format: "%.\(abs(pct) >= 10 ? 0 : 1)f%%", abs(pct))
        let sign = pct >= 0 ? "+" : "−"
        return "\(sign)\(formatted)"
    }

    private func signedMoney(_ value: Decimal) -> String {
        let formatted = DashboardViewModel.money(abs(value))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return formatted
    }

    private func toneColor(for value: Decimal) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.secondaryText
    }
}
