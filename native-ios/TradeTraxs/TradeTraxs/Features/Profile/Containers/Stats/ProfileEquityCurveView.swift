import Charts
import SwiftUI

/// Native Charts equity curve, Apple Stocks-style axes, grid, and scrub overlay.
///
/// Data shape matches web `ProfileEquityLineChart` via ``ProfileStatisticsMetrics/EquityPoint``.
struct ProfileEquityCurveView: View {
    let points: [ProfileStatisticsMetrics.EquityPoint]
    private let horizontalLayout: ProfileEquityCurveChartHorizontalLayout
    private let displaySeries: ProfileEquityCurveDisplaySeries

    @Environment(\.themeColors) private var colors
    @State private var selectedTradeIndex: Int?
    @State private var selectedPlotDate: Date?

    init(
        points: [ProfileStatisticsMetrics.EquityPoint],
        horizontalLayout: ProfileEquityCurveChartHorizontalLayout = .standard
    ) {
        self.points = points
        self.horizontalLayout = horizontalLayout
        self.displaySeries = ProfileEquityCurveDisplaySeries.build(from: points)
    }

    var body: some View {
        Group {
            if displaySeries.renderPoints.count >= 2 {
                chart
            } else if let only = displaySeries.renderPoints.first {
                Text(StatsContainerView.equityMoneyText(only.equity))
                    .experienceStyle(.callout, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No equity data")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var renderPoints: [ProfileEquityCurveChartModel.RenderPoint] {
        displaySeries.renderPoints
    }

    private var usesTimelineAxis: Bool {
        displaySeries.xAxisMode == .timeline
    }

    private var showsPersonalDrawdownFloor: Bool {
        renderPoints.contains { $0.drawdownFloorY != nil }
    }

    private var equityInterpolation: InterpolationMethod {
        showsPersonalDrawdownFloor ? .linear : .catmullRom
    }

    private var tradeIndexDomain: ClosedRange<Int> {
        ProfileEquityCurveChartModel.tradeIndexDomain(
            for: renderPoints,
            horizontalLayout: horizontalLayout
        )
    }

    private var timelineDomain: ClosedRange<Date>? {
        ProfileEquityCurveChartModel.timelineDomain(
            for: renderPoints,
            horizontalLayout: horizontalLayout
        )
    }

    private var yDomain: ClosedRange<Double> {
        ProfileEquityCurveChartModel.yDomain(for: renderPoints)
    }

    private var chart: some View {
        Chart {
            ForEach(renderPoints) { point in
                equityMarks(for: point)
            }

            if showsPersonalDrawdownFloor {
                ForEach(renderPoints) { point in
                    if let floorY = point.drawdownFloorY {
                        drawdownMark(for: point, floorY: floorY)
                    }
                }
            }

            if let selected {
                selectionMarks(for: selected)
            }
        }
        .chartYScale(domain: yDomain, type: .linear)
        .modifier(EquityCurveXAxisModifier(
            usesTimeline: usesTimelineAxis,
            horizontalLayout: horizontalLayout,
            tradeIndexDomain: tradeIndexDomain,
            timelineDomain: timelineDomain,
            tradeAxisValues: tradeAxisValues,
            timelineAxisValues: timelineAxisValues,
            tradeLabel: xLabel(forTradeIndex:),
            timelineLabel: timelineLabel(for:),
            colors: colors,
            selectedTradeIndex: $selectedTradeIndex,
            selectedPlotDate: $selectedPlotDate,
            snapTimeline: snapTimelineSelectionIfNeeded
        ))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colors.border.opacity(0.35))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colors.border.opacity(0.45))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(yLabel(raw))
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(colors.tertiaryText)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let selected,
                   let xPos = selectionXPosition(proxy: proxy),
                   let anchor = proxy.plotFrame
                {
                    let plotFrame = geo[anchor]
                    overlayCard(for: selected)
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
        .padding(.horizontal, horizontalLayout == .dashboard ? 0 : ExperienceSpacing.xxs)
        .padding(.top, ExperienceSpacing.xs)
    }

    // MARK: - Chart marks

    @ChartContentBuilder
    private func equityMarks(for point: ProfileEquityCurveChartModel.RenderPoint) -> some ChartContent {
        if usesTimelineAxis, let time = point.plotTime {
            AreaMark(
                x: .value(ProfileEquityCurveChartModel.timelineXPlottable, time),
                yStart: .value(ProfileEquityCurveChartModel.balanceYPlottable, yDomain.lowerBound),
                yEnd: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY),
                series: .value("Series", "Equity")
            )
            .interpolationMethod(equityInterpolation)
            .foregroundStyle(equityFillGradient)

            LineMark(
                x: .value(ProfileEquityCurveChartModel.timelineXPlottable, time),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY),
                series: .value("Series", "Equity")
            )
            .interpolationMethod(equityInterpolation)
            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .foregroundStyle(equityLineGradient)
        } else {
            AreaMark(
                x: .value(ProfileEquityCurveChartModel.tradeXPlottable, point.tradeIndex),
                yStart: .value(ProfileEquityCurveChartModel.balanceYPlottable, yDomain.lowerBound),
                yEnd: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY),
                series: .value("Series", "Equity")
            )
            .interpolationMethod(equityInterpolation)
            .foregroundStyle(equityFillGradient)

            LineMark(
                x: .value(ProfileEquityCurveChartModel.tradeXPlottable, point.tradeIndex),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY),
                series: .value("Series", "Equity")
            )
            .interpolationMethod(equityInterpolation)
            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .foregroundStyle(equityLineGradient)
        }
    }

    @ChartContentBuilder
    private func drawdownMark(
      for point: ProfileEquityCurveChartModel.RenderPoint,
      floorY: Double
    ) -> some ChartContent {
        if usesTimelineAxis, let time = point.plotTime {
            LineMark(
                x: .value(ProfileEquityCurveChartModel.timelineXPlottable, time),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, floorY),
                series: .value("Series", "Drawdown floor")
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
            .foregroundStyle(colors.loss.opacity(0.8))
        } else {
            LineMark(
                x: .value(ProfileEquityCurveChartModel.tradeXPlottable, point.tradeIndex),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, floorY),
                series: .value("Series", "Drawdown floor")
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
            .foregroundStyle(colors.loss.opacity(0.8))
        }
    }

    @ChartContentBuilder
    private func selectionMarks(for point: SelectionPoint) -> some ChartContent {
        if usesTimelineAxis, let time = point.plotTime {
            RuleMark(x: .value(ProfileEquityCurveChartModel.timelineXPlottable, time))
                .foregroundStyle(colors.tertiaryText.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            PointMark(
                x: .value(ProfileEquityCurveChartModel.timelineXPlottable, time),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY)
            )
            .symbolSize(64)
            .foregroundStyle(colors.accent)
        } else {
            RuleMark(x: .value(ProfileEquityCurveChartModel.tradeXPlottable, point.tradeIndex))
                .foregroundStyle(colors.tertiaryText.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            PointMark(
                x: .value(ProfileEquityCurveChartModel.tradeXPlottable, point.tradeIndex),
                y: .value(ProfileEquityCurveChartModel.balanceYPlottable, point.equityY)
            )
            .symbolSize(64)
            .foregroundStyle(colors.accent)
        }
    }

    private var equityFillGradient: LinearGradient {
        LinearGradient(
            colors: [colors.accent.opacity(0.22), colors.accent.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var equityLineGradient: LinearGradient {
        LinearGradient(
            colors: [colors.accent, colors.profit],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func selectionXPosition(proxy: ChartProxy) -> CGFloat? {
        guard let selected else { return nil }
        if usesTimelineAxis, let time = selected.plotTime {
            return proxy.position(forX: time)
        }
        return proxy.position(forX: selected.tradeIndex)
    }

    private func snapTimelineSelectionIfNeeded() {
        guard usesTimelineAxis, let raw = selectedPlotDate else { return }
        guard let snapped = ProfileEquityCurveChartModel.nearestPlotTime(to: raw, in: renderPoints) else { return }
        if abs(snapped.timeIntervalSince(raw)) > 1 {
            selectedPlotDate = snapped
        }
    }

    // MARK: - Selection overlay

    private func overlayCard(for point: SelectionPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.dateLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(colors.secondaryText)
            Text(StatsContainerView.equityMoneyText(point.equity))
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(point.equity >= 0 ? colors.profit : colors.loss)
            if let net = point.periodNetPnL, net != 0 {
                Text("P&L \(NumberDisplay.signedMoney(net))")
                    .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(net >= 0 ? colors.profit : colors.loss)
            }
            if let floorY = point.drawdownFloorY {
                Text("Floor \(StatsContainerView.equityMoneyText(Decimal(floorY)))")
                    .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.loss.opacity(0.9))
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .experienceFloatingPanelBackground(
            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(point.dateLabel), \(StatsContainerView.equityMoneyText(point.equity))")
    }

    // MARK: - Chart model

    private struct SelectionPoint {
        var tradeIndex: Int
        var plotTime: Date?
        var equity: Decimal
        var equityY: Double
        var drawdownFloorY: Double?
        var periodNetPnL: Decimal?
        var scrubPoint: ProfileEquityCurveAggregation.ScrubPoint

        var dateLabel: String {
            ProfileEquityCurveAggregation.scrubDateLabel(for: scrubPoint)
        }
    }

    private var selected: SelectionPoint? {
        let point: ProfileEquityCurveChartModel.RenderPoint?
        if usesTimelineAxis {
            guard let date = selectedPlotDate,
                  let match = renderPoints.min(by: { lhs, rhs in
                      let left = lhs.plotTime ?? .distantPast
                      let right = rhs.plotTime ?? .distantPast
                      return abs(left.timeIntervalSince(date)) < abs(right.timeIntervalSince(date))
                  })
            else { return nil }
            point = match
        } else {
            guard let tradeIndex = selectedTradeIndex else { return nil }
            point = renderPoints.first { $0.tradeIndex == tradeIndex }
                ?? renderPoints.first {
                    $0.tradeIndex == ProfileEquityCurveChartModel.nearestTradeIndex(
                        to: tradeIndex,
                        in: renderPoints
                    )
                }
        }
        guard let point else { return nil }
        let scrub = ProfileEquityCurveAggregation.ScrubPoint(
            equity: point.equity,
            drawdownFloor: point.drawdownFloorY.map { Decimal($0) },
            anchorDate: point.date,
            periodStart: point.periodStart,
            periodEnd: point.periodEnd,
            periodNetPnL: point.periodNetPnL ?? 0,
            detailLevel: point.detailLevel,
            tradesInBucket: point.tradesInBucket
        )
        return SelectionPoint(
            tradeIndex: point.tradeIndex,
            plotTime: point.plotTime,
            equity: point.equity,
            equityY: point.equityY,
            drawdownFloorY: point.drawdownFloorY,
            periodNetPnL: point.periodNetPnL,
            scrubPoint: scrub
        )
    }

    private var tradeAxisValues: [Int] {
        guard let last = renderPoints.map(\.tradeIndex).max(), last > 0 else { return [0] }
        if last < 3 { return Array(0...last) }
        let mid = last / 2
        return [0, mid, last]
    }

    private var timelineAxisValues: [Date] {
        let stamps = renderPoints.compactMap(\.plotTime).sorted()
        guard let first = stamps.first, let last = stamps.last, first < last else { return stamps }
        if stamps.count < 3 { return stamps }
        return [first, stamps[stamps.count / 2], last]
    }

    private func xLabel(forTradeIndex index: Int) -> String {
        if let point = renderPoints.first(where: { $0.tradeIndex == index }), let date = point.date {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: date)
        }
        return "\(index + 1)"
    }

    private func timelineLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMyy")
        return formatter.string(from: date)
    }

    private func yLabel(_ value: Double) -> String {
        NumberDisplay.compactEquityAxis(value)
    }
}

// MARK: - X axis + scrub selection

private struct EquityCurveXAxisModifier: ViewModifier {
    let usesTimeline: Bool
    let horizontalLayout: ProfileEquityCurveChartHorizontalLayout
    let tradeIndexDomain: ClosedRange<Int>
    let timelineDomain: ClosedRange<Date>?
    let tradeAxisValues: [Int]
    let timelineAxisValues: [Date]
    let tradeLabel: (Int) -> String
    let timelineLabel: (Date) -> String
    let colors: SemanticColorPalette
    @Binding var selectedTradeIndex: Int?
    @Binding var selectedPlotDate: Date?
    let snapTimeline: () -> Void

    func body(content: Content) -> some View {
        if usesTimeline, let timelineDomain {
            applyDashboardXScale(domain: timelineDomain, to: content)
                .chartXAxis {
                    AxisMarks(values: timelineAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.45))
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(timelineLabel(date))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .offset(x: xAxisLabelHorizontalOffset(for: date, in: timelineAxisValues))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedPlotDate)
                .onChange(of: selectedPlotDate) { _, _ in snapTimeline() }
        } else {
            applyDashboardXScale(domain: tradeIndexDomain, to: content)
                .chartXAxis {
                    AxisMarks(values: tradeAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.45))
                        if let index = value.as(Int.self) {
                            AxisValueLabel {
                                Text(tradeLabel(index))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .offset(x: xAxisLabelHorizontalOffset(for: index, in: tradeAxisValues))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedTradeIndex)
        }
    }

    /// Nudges first/last labels inward while keeping every label on the chart’s shared X-axis baseline.
    private func xAxisLabelHorizontalOffset(for date: Date, in values: [Date]) -> CGFloat {
        guard let first = values.first, let last = values.last, values.count > 1 else { return 0 }
        if datesMatchForAxisLabel(date, first) { return 10 }
        if datesMatchForAxisLabel(date, last) { return -10 }
        return 0
    }

    private func xAxisLabelHorizontalOffset(for index: Int, in values: [Int]) -> CGFloat {
        guard let first = values.first, let last = values.last, values.count > 1 else { return 0 }
        if index == first { return 10 }
        if index == last { return -10 }
        return 0
    }

    private func datesMatchForAxisLabel(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    @ViewBuilder
    private func applyDashboardXScale(domain: ClosedRange<Date>, to content: Content) -> some View {
        if let trailingInset = horizontalLayout.xPlotTrailingInset {
            content.chartXScale(
                domain: domain,
                range: .plotDimension(startPadding: 0, endPadding: trailingInset)
            )
        } else {
            content.chartXScale(domain: domain)
        }
    }

    @ViewBuilder
    private func applyDashboardXScale(domain: ClosedRange<Int>, to content: Content) -> some View {
        if let trailingInset = horizontalLayout.xPlotTrailingInset {
            content.chartXScale(
                domain: domain,
                range: .plotDimension(startPadding: 0, endPadding: trailingInset)
            )
        } else {
            content.chartXScale(domain: domain)
        }
    }
}