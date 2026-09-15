import Charts
import SwiftUI

struct CalendarYearView: View {
    let overview: TradingYearOverview
    let onSelectMonth: (Int) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            CalendarYearSummaryBar(overview: overview)
            CalendarYearMonthGrid(months: overview.months, onSelectMonth: onSelectMonth)
            CalendarYearMonthlyPnLChart(months: overview.months)
        }
        .accessibilityIdentifier("calendar.year")
    }
}

private struct CalendarYearSummaryBar: View {
    let overview: TradingYearOverview

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        ProfileStatsDashboardSection(
            title: "Year Summary",
            accessibilityID: "calendar.yearSummary"
        ) {
            ProfileStatsDashboardCard {
                HStack(spacing: 0) {
                    metric(
                        label: "Year P&L",
                        value: CalendarFormatting.fullPnL(overview.netPnL),
                        tone: overview.netPnL,
                        emphasis: true
                    )
                    divider
                    metric(
                        label: "Trading Days",
                        value: "\(overview.tradingDayCount)",
                        tone: nil,
                        emphasis: false
                    )
                    divider
                    metric(
                        label: "Win Rate",
                        value: overview.tradeWinRate.map(NumberDisplay.winRate) ?? "—",
                        tone: nil,
                        emphasis: false
                    )
                    divider
                    metric(
                        label: "Best Month",
                        value: bestMonthValue,
                        tone: overview.bestMonthPnL,
                        emphasis: false
                    )
                }
            }
        }
    }

    private var bestMonthValue: String {
        guard let abbrev = overview.bestMonthAbbreviation, let pnl = overview.bestMonthPnL else {
            return "—"
        }
        return "\(abbrev) \(CalendarFormatting.compactPnL(pnl))"
    }

    private var divider: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(width: ExperienceBorder.hairline)
            .padding(.vertical, ExperienceSpacing.xxs)
    }

    private func metric(label: String, value: String, tone: Decimal?, emphasis: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.25)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(
                    emphasis
                        ? .system(.title3, design: .rounded).weight(.bold).monospacedDigit()
                        : .system(.caption, design: .rounded).weight(.semibold).monospacedDigit()
                )
                .foregroundStyle(valueColor(for: tone, emphasis: emphasis))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func valueColor(for tone: Decimal?, emphasis: Bool) -> Color {
        guard let tone else { return colors.primaryText }
        return theme.metricColor(for: NSDecimalNumber(decimal: tone).doubleValue)
    }
}

private struct CalendarYearMonthGrid: View {
    let months: [TradingYearMonthCard]
    let onSelectMonth: (Int) -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: ExperienceSpacing.xs), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: ExperienceSpacing.xs) {
            ForEach(months) { card in
                Button {
                    onSelectMonth(card.month)
                } label: {
                    VStack(spacing: ExperienceSpacing.xxs) {
                        Text(card.abbreviation)
                            .font(.system(.caption2, design: .default).weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                        Text(displayPnL(for: card))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(pnlColor(for: card))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, ExperienceSpacing.xxs)
                    .background(background(for: card), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(card.isFutureMonth)
                .accessibilityIdentifier("calendar.year.month.\(card.month)")
                .accessibilityLabel("\(card.abbreviation), \(displayPnL(for: card))")
            }
        }
    }

    private func displayPnL(for card: TradingYearMonthCard) -> String {
        if card.isFutureMonth {
            return CalendarFormatting.compactPnL(0)
        }
        if card.summary.tradingDayCount == 0, card.summary.tradeCount == 0 {
            return CalendarFormatting.compactPnL(0)
        }
        return CalendarFormatting.compactPnL(card.summary.netPnL)
    }

    private func pnlColor(for card: TradingYearMonthCard) -> Color {
        if card.isFutureMonth || (card.summary.tradingDayCount == 0 && card.summary.tradeCount == 0) {
            return colors.secondaryText
        }
        return theme.metricColor(for: NSDecimalNumber(decimal: card.summary.netPnL).doubleValue)
    }

    private func background(for card: TradingYearMonthCard) -> Color {
        if card.isFutureMonth || (card.summary.tradingDayCount == 0 && card.summary.tradeCount == 0) {
            return colors.fillTertiary.opacity(0.35)
        }
        if card.summary.netPnL > 0 { return colors.profit.opacity(0.12) }
        if card.summary.netPnL < 0 { return colors.loss.opacity(0.12) }
        return colors.neutralMetric.opacity(0.12)
    }
}

private struct CalendarYearMonthlyPnLChart: View {
    let months: [TradingYearMonthCard]

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        ProfileStatsDashboardSection(
            title: "Monthly P&L",
            accessibilityID: "calendar.year.monthlyChart"
        ) {
            ProfileStatsDashboardCard {
                Chart(chartPoints) { point in
                    BarMark(
                        x: .value("Month", point.label),
                        y: .value("P&L", point.value)
                    )
                    .foregroundStyle(barColor(for: point.value))
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Monthly profit and loss chart")
            }
        }
    }

    private struct ChartPoint: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
    }

    private var chartPoints: [ChartPoint] {
        months.map { card in
            let amount: Double
            if card.isFutureMonth {
                amount = 0
            } else {
                amount = NSDecimalNumber(decimal: card.summary.netPnL).doubleValue
            }
            return ChartPoint(label: card.abbreviation, value: amount)
        }
    }

    private func barColor(for value: Double) -> Color {
        theme.metricColor(for: value).opacity(0.9)
    }
}
