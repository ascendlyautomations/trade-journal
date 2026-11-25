import Charts
import SwiftUI

struct LeaderboardCurveChartView: View {
    let points: [LeaderboardCurveChartPoint]
    let category: LeaderboardCategory
    let metricFormat: LeaderboardCurveV1.MetricFormat

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    private var prepared: LeaderboardCurveChartData.Prepared {
        LeaderboardCurveChartData.prepare(points: points)
    }

    private var selectedPoint: LeaderboardCurveChartPoint? {
        guard let selectedDate else { return nil }
        return nearestPoint(to: selectedDate, in: prepared.days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if prepared.days.count >= 2, !prepared.marks.isEmpty {
                Chart {
                    ForEach(prepared.marks) { mark in
                        lineMark(for: mark)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Selected", selectedPoint.date, unit: .day))
                            .foregroundStyle(colors.tertiaryText.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: .automatic(includesZero: includesZero))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisDate(date))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text(formatMetricValue(raw))
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .onChange(of: selectedDate) { _, newValue in
                    guard let newValue else { return }
                    if let snapped = nearestPoint(to: newValue, in: prepared.days)?.date, snapped != newValue {
                        selectedDate = snapped
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let selectedPoint,
                           let xPos = proxy.position(forX: selectedPoint.date),
                           let plotFrame = proxy.plotFrame.map({ geometry[$0] })
                        {
                            let anchorX = plotFrame.minX + xPos
                            let containerMinX = LeaderboardCurveChartTooltip.horizontalEdgeInset
                            let containerMaxX = geometry.size.width - LeaderboardCurveChartTooltip.horizontalEdgeInset
                            let centerX = LeaderboardCurveTooltipPlacement.clampedCenterX(
                                anchorX: anchorX,
                                containerMinX: containerMinX,
                                containerMaxX: containerMaxX
                            )

                            LeaderboardCurveChartTooltip(
                                point: selectedPoint,
                                prepared: prepared,
                                category: category,
                                metricFormat: metricFormat,
                                colors: colors,
                                dateText: axisDate(selectedPoint.date),
                                valueText: { value in
                                    LeaderboardCurveTooltipFormatting.format(
                                        value,
                                        category: category,
                                        metricFormat: metricFormat
                                    )
                                },
                                seriesColor: seriesColor
                            )
                            .position(
                                x: centerX,
                                y: plotFrame.minY + LeaderboardCurveChartTooltip.verticalOffset
                            )
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityIdentifier("leaderboard.curve.chart")

                legend
            } else {
                Text("Not enough history to chart this timeframe yet.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                    .accessibilityIdentifier("leaderboard.curve.empty")
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: ExperienceSpacing.md) {
            legendItem(LeaderboardCurveSeries.highest)
            legendItem(LeaderboardCurveSeries.you)
            legendItem(LeaderboardCurveSeries.average)
            legendItem(LeaderboardCurveSeries.lowest)
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(colors.secondaryText)
    }

    @ChartContentBuilder
    private func lineMark(for mark: LeaderboardCurvePlotMark) -> some ChartContent {
        LineMark(
            x: .value("Day", mark.date, unit: .day),
            y: .value("Value", mark.value),
            series: .value("Series", mark.series.chartKey)
        )
        .interpolationMethod(.linear)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .foregroundStyle(seriesColor(mark.series))
    }

    private func legendItem(_ series: LeaderboardCurveSeries) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(seriesColor(series))
                .frame(width: 6, height: 6)
            Text(series.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func seriesColor(_ series: LeaderboardCurveSeries) -> Color {
        switch series {
        case .highest:
            return colors.profit
        case .lowest:
            return colors.loss
        case .average:
            return colorScheme == .dark ? Color(hex: 0x4A8FD4) : Color(hex: 0x1B4F8A)
        case .you:
            return colorScheme == .dark ? Color(hex: 0xFF9F3A) : Color(hex: 0xE07010)
        }
    }

    private func nearestPoint(to date: Date, in days: [LeaderboardCurveChartPoint]) -> LeaderboardCurveChartPoint? {
        days.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private var includesZero: Bool {
        switch category {
        case .pnl, .expectancy:
            return true
        default:
            return metricFormat != .percent
        }
    }

    private func axisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return formatter.string(from: date)
    }

    private func formatMetricValue(_ value: Double) -> String {
        if category.curveUsesIntegerAxis {
            return NumberDisplay.integer(Int(value.rounded()))
        }
        switch metricFormat {
        case .currency:
            return TradeDisplay.pnlText(Money(amount: Decimal(value)))
        case .percent:
            if category == .winRate {
                return NumberDisplay.percent(value * 100, minimumFractionDigits: 1, maximumFractionDigits: 1)
            }
            return NumberDisplay.percent(value, minimumFractionDigits: 1, maximumFractionDigits: 1)
        case .ratio:
            if category == .winStreak || category == .followers {
                return NumberDisplay.integer(Int(value.rounded()))
            }
            return NumberDisplay.ratio(Decimal(value), fractionDigits: 2)
        }
    }
}

private extension LeaderboardCurveSeries {
    var title: String {
        switch self {
        case .highest: return "Highest"
        case .you: return "You"
        case .average: return "Average"
        case .lowest: return "Lowest"
        }
    }
}