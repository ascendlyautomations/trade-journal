import SwiftUI

/// Performance summary card for Backtest Lab (trade counts + 2×3 metric grid).
struct BacktestLabMetricsGrid: View {
    let snapshot: BacktestLabMetrics.Snapshot

    @Environment(\.themeColors) private var colors

    private let gridColumns = [
        GridItem(.flexible(), spacing: ExperienceSpacing.sm, alignment: .topLeading),
        GridItem(.flexible(), spacing: ExperienceSpacing.sm, alignment: .topLeading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            tradeOutcomesLine

            LazyVGrid(columns: gridColumns, spacing: ExperienceSpacing.sm) {
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
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .featured)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("backtest.lab.metrics")
    }

    private var tradeOutcomesLine: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Text("Trades: \(snapshot.tradeCount)")
                .experienceStyle(.footnote, color: colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Wins: \(snapshot.winCount)")
                .experienceStyle(.footnote, color: colors.profit)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Losses: \(snapshot.lossCount)")
                .experienceStyle(.footnote, color: colors.loss)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("backtest.lab.metrics.winsLosses")
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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