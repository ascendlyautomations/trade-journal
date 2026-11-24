import SwiftUI

/// Performance metrics, 4 + 3 grid for Backtest Lab (web `/backtest` parity).
struct BacktestLabMetricsGrid: View {
    let snapshot: BacktestLabMetrics.Snapshot

    @Environment(\.themeColors) private var colors

    private let row1Columns = Array(
        repeating: GridItem(.flexible(), spacing: ExperienceSpacing.xs, alignment: .top),
        count: 4
    )
    private let row2Columns = Array(
        repeating: GridItem(.flexible(), spacing: ExperienceSpacing.xs, alignment: .top),
        count: 3
    )

    private let tileMinHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            LazyVGrid(columns: row1Columns, spacing: ExperienceSpacing.xs) {
                metricTile(
                    label: "Trades",
                    value: "\(snapshot.tradeCount)",
                    tone: .neutral
                )
                metricTile(
                    label: "Win Rate",
                    value: String(format: "%.1f%%", snapshot.winRatePercent),
                    tone: .neutral
                )
                metricTile(
                    label: "Total P&L",
                    value: TradeDisplay.pnlText(Money(amount: snapshot.totalPnL)),
                    tone: pnlTone(snapshot.totalPnL)
                )
                metricTile(
                    label: "Avg R:R",
                    value: snapshot.averageRR.map { TradeDisplay.compactRRText(Decimal($0)) ?? "–" } ?? "–",
                    tone: .neutral
                )
            }

            LazyVGrid(columns: row2Columns, spacing: ExperienceSpacing.xs) {
                metricTile(
                    label: "Profit Factor",
                    value: BacktestLabMetrics.formatProfitFactor(snapshot.profitFactor),
                    tone: .neutral
                )
                metricTile(
                    label: "Avg Win",
                    value: BacktestLabMetrics.formatAverageWin(snapshot.averageWin),
                    tone: .positive
                )
                metricTile(
                    label: "Avg Loss",
                    value: BacktestLabMetrics.formatAverageLoss(snapshot.averageLoss),
                    tone: .negative
                )
            }
        }
        .padding(ExperienceSpacing.sm)
        .experienceTradingRulesCard(prominence: .featured)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("backtest.lab.metrics")
    }

    private func pnlTone(_ pnl: Decimal) -> DashboardMetricTone {
        if pnl > 0 { return .positive }
        if pnl < 0 { return .negative }
        return .neutral
    }

    private func metricTile(
        label: String,
        value: String,
        tone: DashboardMetricTone
    ) -> some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            Text(label)
                .experienceStyle(.caption2, color: colors.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: tileMinHeight, alignment: .center)
        .padding(.horizontal, ExperienceSpacing.xxs)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}