import Charts
import SwiftUI

struct CalendarYearView: View {
    let overview: TradingYearOverview
    let onSelectMonth: (Int) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
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
                .padding(.vertical, -ExperienceSpacing.xxs)
            }
        }
    }

    private var bestMonthValue: String {
        overview.bestMonthAbbreviation ?? "—"
    }

    private var divider: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(width: ExperienceBorder.hairline)
            .padding(.vertical, 2)
    }

    private func metric(label: String, value: String, tone: Decimal?) -> some View {
        VStack(spacing: 2) {
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
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
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
    @Environment(\.colorScheme) private var colorScheme

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
                .buttonStyle(.experiencePlain)
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
        let isNeutral = card.isFutureMonth
            || (card.summary.tradingDayCount == 0 && card.summary.tradeCount == 0)
        let netPnL = card.isFutureMonth ? 0 : card.summary.netPnL
        return CalendarCellAppearance.yearMonthCardFill(
            colors: colors,
            colorScheme: colorScheme,
            isNeutral: isNeutral,
            netPnL: netPnL
        )
    }
}

private struct CalendarYearMonthlyPnLChart: View {
    let months: [TradingYearMonthCard]

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @State private var selectedMonth: Int?

    var body: some View {
        ProfileStatsDashboardSection(
            title: "Monthly P&L",
            accessibilityID: "calendar.year.monthlyChart"
        ) {
            ProfileStatsDashboardCard {
                Chart {
                    ForEach(chartPoints) { point in
                        BarMark(
                            x: .value("Month", point.month),
                            y: .value("P&L", point.value)
                        )
                        .foregroundStyle(
                            barColor(for: point.netPnL)
                                .opacity(barOpacity(for: point.month))
                        )
                        .cornerRadius(3)
                    }

                    if let selectedMonth {
                        RuleMark(x: .value("Selected", selectedMonth))
                            .foregroundStyle(colors.tertiaryText.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: 1...12)
                .chartYScale(domain: yAxisScale.lowerBound...yAxisScale.upperBound)
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisScale.tickValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text(CalendarMonthlyPnLYAxisScale.formatTickLabel(raw))
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisMonths) { value in
                        AxisValueLabel(centered: true) {
                            if let month = value.as(Int.self) {
                                Text("\(month)")
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Months (Jan – Dec)", alignment: .center)
                .chartXSelection(value: $selectedMonth)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if let selectedMonth,
                           let card = months.first(where: { $0.month == selectedMonth }),
                           let xPos = proxy.position(forX: selectedMonth),
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
                .frame(height: 132)
                .accessibilityLabel("Monthly profit and loss chart")
            }
        }
    }

    private struct ChartPoint: Identifiable {
        var id: Int { month }
        var month: Int
        var netPnL: Decimal
        var value: Double
    }

    private var yAxisScale: CalendarMonthlyPnLYAxisScale.Result {
        CalendarMonthlyPnLYAxisScale.resolve(
            monthlyValues: chartPoints.map(\.value)
        )
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
                month: card.month,
                netPnL: netPnL,
                value: NSDecimalNumber(decimal: netPnL).doubleValue
            )
        }
    }

    private var xAxisMonths: [Int] {
        Array(1...12)
    }

    private func barColor(for netPnL: Decimal) -> Color {
        theme.metricColor(for: NSDecimalNumber(decimal: netPnL).doubleValue)
    }

    private func barOpacity(for month: Int) -> Double {
        guard let selectedMonth else { return 0.9 }
        return selectedMonth == month ? 0.95 : 0.38
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
        .experienceFloatingPanelBackground(
            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        )
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
