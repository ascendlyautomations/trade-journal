import SwiftUI

struct CalendarMonthSummaryBar: View {
    let summary: TradingMonthSummary

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Month summary")
                .experienceStyle(.footnote, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.md) {
                metric(
                    "Net P&L",
                    CalendarFormatting.fullPnL(summary.netPnL),
                    tone: summary.netPnL
                )
                metric(
                    "Trades",
                    "\(summary.tradeCount)",
                    tone: nil
                )
                metric(
                    "Days",
                    "\(summary.tradingDayCount)",
                    tone: nil
                )
            }

            HStack(spacing: ExperienceSpacing.md) {
                metric(
                    "Win days",
                    "\(summary.winningDayCount)",
                    tone: summary.winningDayCount > 0 ? 1 : nil
                )
                metric(
                    "Loss days",
                    "\(summary.losingDayCount)",
                    tone: summary.losingDayCount > 0 ? -1 : nil
                )
                if let avg = summary.averageDailyPnL {
                    metric("Avg day", CalendarFormatting.compactPnL(avg), tone: avg)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .accessibilityIdentifier("calendar.monthSummary")
    }

    private func metric(_ label: String, _ value: String, tone: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(value)
                .experienceStyle(
                    .headline,
                    color: {
                        guard let tone else { return colors.primaryText }
                        return theme.metricColor(for: NSDecimalNumber(decimal: tone).doubleValue)
                    }()
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
