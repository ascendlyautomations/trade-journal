import SwiftUI

/// Standard Performance Report key metrics grid (weekly, monthly, yearly, custom).
struct ReportKeyMetricsGrid: View {
    let metrics: TradingReportMetrics

    @Environment(\.themeColors) private var colors

    var body: some View {
        LazyVGrid(
            columns: ReportKeyMetricsLayout.gridColumns,
            spacing: ReportKeyMetricsLayout.gridRowSpacing
        ) {
            metricCell(
                "Net P&L",
                metrics.knownResultCount > 0 ? formatPnl(metrics.netPnl) : "–",
                tone: metrics.knownResultCount > 0 ? pnlTone(metrics.netPnl) : nil
            )
            metricCell("Total Trades", NumberDisplay.integer(metrics.tradesTaken))
            metricCell(
                "Win Rate",
                metrics.knownResultCount > 0
                    ? NumberDisplay.percent(metrics.winRate, minimumFractionDigits: 1, maximumFractionDigits: 1)
                    : "–"
            )
            metricCell(
                "Profit Factor",
                metrics.profitFactor.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–"
            )
            metricCell("Avg Target R:R", metrics.averageRr.map(formatRR) ?? "–")
            metricCell("Avg Reached R:R", metrics.averageReachedRr.map(formatRR) ?? "–")
            metricCell("Average Winner", formatOptionalMoney(metrics.averageWinner))
            metricCell("Average Loser", formatOptionalMoney(metrics.averageLoser))
            metricCell("Expectancy", formatOptionalMoney(metrics.expectancy))
            metricCell("Max Drawdown", formatOptionalMoney(metrics.maxDrawdown))
            metricCell(
                "Best Trade",
                formatOptionalMoney(metrics.bestTrade),
                tone: metrics.bestTrade.map { pnlTone($0) }
            )
            metricCell(
                "Worst Trade",
                formatOptionalMoney(metrics.worstTrade),
                tone: metrics.worstTrade.map { pnlTone($0) }
            )
            labelAndPnLMetricCell(
                "Best Day",
                dayLabel: metrics.bestDayLabel,
                pnl: metrics.bestDayPnl
            )
            labelAndPnLMetricCell(
                "Worst Day",
                dayLabel: metrics.worstDayLabel,
                pnl: metrics.worstDayPnl
            )
            metricCell(
                "Winning Days",
                metrics.winningDays.map { NumberDisplay.integer($0) } ?? "–"
            )
            metricCell(
                "Losing Days",
                metrics.losingDays.map { NumberDisplay.integer($0) } ?? "–"
            )
            labelAndPnLMetricCell(
                "Best Session",
                dayLabel: metrics.bestSessionLabel,
                pnl: metrics.bestSessionPnl
            )
            labelAndPnLMetricCell(
                "Worst Session",
                dayLabel: metrics.worstSessionLabel,
                pnl: metrics.worstSessionPnl
            )
            metricCell("Most Traded", metrics.mostTradedSymbol ?? "–")
            metricCell(
                "Avg Hold Time",
                metrics.averageHoldTimeSeconds.map(formatHold) ?? "–"
            )
        }
    }

    private func labelAndPnLMetricCell(_ title: String, dayLabel: String?, pnl: Double?) -> some View {
        VStack(alignment: .leading, spacing: ReportKeyMetricsLayout.tileLabelValueSpacing) {
            Text(title.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            if let dayLabel, let pnl {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(formatPnl(pnl))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(pnlTone(pnl))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("–")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(ReportKeyMetricsLayout.tileContentPadding)
        .reportKeyMetricsTileFrame()
        .reportKeyMetricsTile()
    }

    private func metricCell(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: ReportKeyMetricsLayout.tileLabelValueSpacing) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone ?? colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(ReportKeyMetricsLayout.tileContentPadding)
        .reportKeyMetricsTileFrame()
        .reportKeyMetricsTile()
    }

    private func pnlTone(_ value: Double) -> Color {
        if value > 0.01 { return colors.profit }
        if value < -0.01 { return colors.loss }
        return colors.primaryText
    }

    private func formatPnl(_ value: Double) -> String {
        NumberDisplay.reportPnL(value)
    }

    private func formatOptionalMoney(_ value: Double?) -> String {
        guard let value else { return "–" }
        return NumberDisplay.money(Decimal(value))
    }

    private func formatRR(_ value: Double) -> String {
        NumberDisplay.decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }

    private func formatHold(_ seconds: Int) -> String {
        TradeHoldDuration.formatSeconds(seconds) ?? "–"
    }
}