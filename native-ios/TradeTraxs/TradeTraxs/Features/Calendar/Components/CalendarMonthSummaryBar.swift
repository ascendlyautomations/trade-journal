import SwiftUI

struct CalendarMonthSummaryBar: View {
    let summary: TradingMonthSummary

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        ProfileStatsDashboardSection(
            title: "Month Summary",
            accessibilityID: "calendar.monthSummary"
        ) {
            ProfileStatsDashboardCard {
                VStack(spacing: ExperienceSpacing.sm) {
                    metricRow(
                        CalendarSummaryMetric(
                            label: "Net P&L",
                            value: CalendarFormatting.fullPnL(summary.netPnL),
                            tone: summary.netPnL,
                            emphasis: true
                        ),
                        CalendarSummaryMetric(
                            label: "Trades",
                            value: "\(summary.tradeCount)",
                            tone: nil,
                            emphasis: false
                        ),
                        CalendarSummaryMetric(
                            label: "Days",
                            value: "\(summary.tradingDayCount)",
                            tone: nil,
                            emphasis: false
                        )
                    )

                    rowDivider

                    metricRow(
                        CalendarSummaryMetric(
                            label: "Win Days",
                            value: "\(summary.winningDayCount)",
                            tone: summary.winningDayCount > 0 ? 1 : nil,
                            emphasis: false
                        ),
                        CalendarSummaryMetric(
                            label: "Loss Days",
                            value: "\(summary.losingDayCount)",
                            tone: summary.losingDayCount > 0 ? -1 : nil,
                            emphasis: false
                        ),
                        CalendarSummaryMetric(
                            label: "Avg Day",
                            value: summary.averageDailyPnL.map(CalendarFormatting.compactPnL) ?? "—",
                            tone: summary.averageDailyPnL,
                            emphasis: false
                        )
                    )
                }
            }
        }
    }

    private func metricRow(_ metrics: CalendarSummaryMetric...) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                metricCell(metric)
                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(colors.border.opacity(0.45))
                        .frame(width: ExperienceBorder.hairline)
                        .padding(.vertical, ExperienceSpacing.xxs)
                }
            }
        }
    }

    private func metricCell(_ metric: CalendarSummaryMetric) -> some View {
        VStack(spacing: 3) {
            Text(metric.label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.25)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.value)
                .font(
                    metric.emphasis
                        ? .system(.title3, design: .rounded).weight(.bold).monospacedDigit()
                        : .system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()
                )
                .foregroundStyle(valueColor(for: metric.tone, emphasis: metric.emphasis))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(colors.separator.opacity(0.55))
            .frame(height: ExperienceBorder.hairline)
    }

    private func valueColor(for tone: Decimal?, emphasis: Bool) -> Color {
        guard let tone else { return colors.primaryText }
        return theme.metricColor(for: NSDecimalNumber(decimal: tone).doubleValue)
    }
}

private struct CalendarSummaryMetric {
    var label: String
    var value: String
    var tone: Decimal?
    var emphasis: Bool
}
