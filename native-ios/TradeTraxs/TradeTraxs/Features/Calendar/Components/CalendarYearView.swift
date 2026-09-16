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
                        tone: overview.netPnL
                    )
                    divider
                    metric(
                        label: "Trade Days",
                        value: "\(overview.tradingDayCount)",
                        tone: nil
                    )
                    divider
                    metric(
                        label: "Win Rate",
                        value: overview.tradeWinRate.map(NumberDisplay.winRate) ?? "—",
                        tone: nil
                    )
                    divider
                    metric(
                        label: "Best Month",
                        value: bestMonthValue,
                        tone: overview.bestMonthPnL
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

    private func metric(label: String, value: String, tone: Decimal?) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.25)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor(for: tone))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func valueColor(for tone: Decimal?) -> Color {
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
    @State private var selectedMonthIndex: Int?

    var body: some View {
        ProfileStatsDashboardSection(
            title: "Monthly P&L",
            accessibilityID: "calendar.year.monthlyChart"
        ) {
            ProfileStatsDashboardCard {
                Chart {
                    ForEach(chartPoints) { point in
                        BarMark(
                            x: .value("Month", point.index),
                            y: .value("P&L", point.value)
                        )
                        .foregroundStyle(
                            barColor(for: point.netPnL)
                                .opacity(barOpacity(for: point.index))
                        )
                        .cornerRadius(3)
                    }

                    if let selectedMonthIndex {
                        RuleMark(x: .value("Selected", selectedMonthIndex))
                            .foregroundStyle(colors.tertiaryText.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                .chartXAxis {
                    AxisMarks(values: xAxisIndices) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self),
                               let point = chartPoints.first(where: { $0.index == index })
                            {
                                Text(point.abbreviation)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedMonthIndex)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if let selectedMonthIndex,
                           let card = months.first(where: { $0.month - 1 == selectedMonthIndex }),
                           let xPos = proxy.position(forX: selectedMonthIndex),
                           let anchor = proxy.plotFrame
                        {
                            let plotFrame = geo[anchor]
                            scrubOverlay(for: card)
                                .position(
                                    x: min(
                                        max(plotFrame.minX + 72, plotFrame.minX + xPos),
                                        plotFrame.maxX - 72
                                    ),
                                    y: plotFrame.minY + 28
                                )
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Monthly profit and loss chart")
            }
        }
    }

    private struct ChartPoint: Identifiable {
        var id: Int { index }
        var index: Int
        var abbreviation: String
        var netPnL: Decimal
        var value: Double
    }

    private var chartPoints: [ChartPoint] {
        months.map { card in
            let netPnL: Decimal
            if card.isFutureMonth {
                netPnL = 0
            } else {
                netPnL = card.summary.netPnL
            }
            return ChartPoint(
                index: card.month - 1,
                abbreviation: card.abbreviation,
                netPnL: netPnL,
                value: NSDecimalNumber(decimal: netPnL).doubleValue
            )
        }
    }

    private var xDomain: ClosedRange<Int> {
        0...max(months.count - 1, 0)
    }

    private var xAxisIndices: [Int] {
        chartPoints.map(\.index)
    }

    private func barColor(for netPnL: Decimal) -> Color {
        theme.metricColor(for: NSDecimalNumber(decimal: netPnL).doubleValue)
    }

    private func barOpacity(for index: Int) -> Double {
        guard let selectedMonthIndex else { return 0.9 }
        return selectedMonthIndex == index ? 0.95 : 0.38
    }

    private func scrubOverlay(for card: TradingYearMonthCard) -> some View {
        let netPnL = card.isFutureMonth ? Decimal(0) : card.summary.netPnL
        return VStack(alignment: .leading, spacing: 2) {
            Text(fullMonthName(card.month))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(colors.secondaryText)
            Text(CalendarFormatting.fullPnL(netPnL))
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(theme.metricColor(for: NSDecimalNumber(decimal: netPnL).doubleValue))
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border.opacity(0.5), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private func fullMonthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.day = 1
        components.year = 2000
        guard let date = Calendar.current.date(from: components) else {
            return "Month \(month)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }
}
