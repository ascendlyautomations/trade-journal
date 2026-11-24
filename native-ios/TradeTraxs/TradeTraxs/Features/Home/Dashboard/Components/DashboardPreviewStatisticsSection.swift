import SwiftUI

/// TraxsPro dashboard preview, scoped KPI grid (report metrics + R:R pair).
struct DashboardPreviewStatisticsSection: View {
    let summary: DashboardChartMetrics.Summary
    let reportMetrics: TradingReportMetrics?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Statistics")
                .experienceStyle(.headline, color: colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ExperienceSpacing.xs),
                    GridItem(.flexible(), spacing: ExperienceSpacing.xs),
                ],
                spacing: ExperienceSpacing.xs
            ) {
                metricCell("Net P&L", formatMoney(summary.netPnL))
                metricCell(
                    "Win Rate",
                    summary.winRate.map {
                        NumberDisplay.percent($0, minimumFractionDigits: 0, maximumFractionDigits: 1)
                    } ?? "–"
                )
                metricCell(
                    "Avg Target RR",
                    summary.averageRR.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–"
                )
                metricCell(
                    "Avg Max R:R",
                    formatOptionalRatio(summary.averageMaxRrReached)
                )
                metricCell("Profit Factor", formatProfitFactor(summary.profitFactor))
                metricCell("Expectancy", summary.expectancy.map(formatMoney) ?? "–")

                if let metrics = reportMetrics {
                    labelAndPnLCell(
                        "Best Day",
                        dayLabel: metrics.bestDayLabel,
                        pnl: metrics.bestDayPnl
                    )
                    labelAndPnLCell(
                        "Worst Day",
                        dayLabel: metrics.worstDayLabel,
                        pnl: metrics.worstDayPnl
                    )
                    labelAndPnLCell(
                        "Best Session",
                        dayLabel: metrics.bestSessionLabel,
                        pnl: metrics.bestSessionPnl
                    )
                    labelAndPnLCell(
                        "Worst Session",
                        dayLabel: metrics.worstSessionLabel,
                        pnl: metrics.worstSessionPnl
                    )
                    metricCell("Trades", NumberDisplay.integer(metrics.tradesTaken))
                    metricCell(
                        "Avg Hold Time",
                        metrics.averageHoldTimeSeconds.map(formatHold) ?? "–"
                    )
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.preview.statistics")
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
    }

    private func labelAndPnLCell(_ title: String, dayLabel: String?, pnl: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    Text(NumberDisplay.reportPnL(pnl))
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
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
    }

    private func pnlTone(_ pnl: Double) -> Color {
        if pnl > 0.01 { return colors.profit }
        if pnl < -0.01 { return colors.loss }
        return colors.primaryText
    }

    private func formatMoney(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }

    private func formatProfitFactor(_ value: Decimal?) -> String {
        guard let value else { return "–" }
        return NumberDisplay.ratio(value, fractionDigits: 2)
    }

    private func formatOptionalRatio(_ value: Decimal?) -> String {
        guard let value else { return "–" }
        return NumberDisplay.ratio(value, fractionDigits: 2)
    }

    private func formatHold(_ seconds: Int) -> String {
        TradeHoldDuration.formatSeconds(seconds) ?? "–"
    }
}