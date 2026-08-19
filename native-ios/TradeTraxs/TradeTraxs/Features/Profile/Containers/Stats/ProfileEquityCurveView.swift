import Charts
import SwiftUI

/// Native Charts equity curve — Apple Stocks-style axes, grid, and scrub overlay.
///
/// Data shape matches web `ProfileEquityLineChart` via ``ProfileStatisticsMetrics/EquityPoint``.
struct ProfileEquityCurveView: View {
    let points: [ProfileStatisticsMetrics.EquityPoint]

    @Environment(\.themeColors) private var colors
    @State private var selectedIndex: Int?

    var body: some View {
        Group {
            if points.count >= 2 {
                chart
            } else if let only = points.first {
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

    private var chart: some View {
        Chart {
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Trade", point.index),
                    y: .value("Equity", point.equityValue)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(
                    LinearGradient(
                        colors: [colors.accent, colors.profit],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // Fill only within the visible Y domain (line → plot bottom).
                // A single-y AreaMark baselines at 0, which sits far below padded
                // equity domains and can bleed past the chart into layout below.
                AreaMark(
                    x: .value("Trade", point.index),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Equity", point.equityValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.22),
                            colors.accent.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            if let selected, let selectedIndex {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(colors.tertiaryText.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Selected", selectedIndex),
                    y: .value("Equity", selected.equityValue)
                )
                .symbolSize(64)
                .foregroundStyle(colors.accent)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colors.border.opacity(0.35))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colors.border.opacity(0.45))
                AxisValueLabel {
                    if let index = value.as(Int.self) {
                        Text(xLabel(for: index))
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
        .chartXSelection(value: $selectedIndex)
        .chartPlotStyle { plotArea in
            // Clip Catmull–Rom overshoot so fill/line never leave the plot.
            plotArea.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let selected, let selectedIndex,
                   let xPos = proxy.position(forX: selectedIndex),
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
        .padding(.top, ExperienceSpacing.xs)
    }

    // MARK: - Selection overlay

    private func overlayCard(for point: ChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.dateLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(colors.secondaryText)
            Text(StatsContainerView.equityMoneyText(point.equity))
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(point.equity >= 0 ? colors.profit : colors.loss)
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
        .accessibilityLabel("\(point.dateLabel), \(StatsContainerView.equityMoneyText(point.equity))")
    }

    // MARK: - Chart model

    private struct ChartPoint: Identifiable {
        var id: Int { index }
        var index: Int
        var equity: Decimal
        var equityValue: Double
        var date: Date?

        var dateLabel: String {
            if let date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter.string(from: date)
            }
            return "Trade \(index + 1)"
        }
    }

    private var chartPoints: [ChartPoint] {
        points.map {
            ChartPoint(
                index: $0.index,
                equity: $0.equity,
                equityValue: NSDecimalNumber(decimal: $0.equity).doubleValue,
                date: $0.date
            )
        }
    }

    private var selected: ChartPoint? {
        guard let selectedIndex else { return nil }
        return chartPoints.first { $0.index == selectedIndex }
    }

    private var xDomain: ClosedRange<Int> {
        let maxIndex = points.map(\.index).max() ?? 1
        return 0...max(1, maxIndex)
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.equityValue)
        let minY = values.min() ?? 0
        let maxY = values.max() ?? 0
        if minY == maxY {
            let pad = max(abs(minY) * 0.1, 10)
            return (minY - pad)...(maxY + pad)
        }
        let pad = (maxY - minY) * 0.12
        return (minY - pad)...(maxY + pad)
    }

    private var xAxisValues: [Int] {
        guard let last = points.map(\.index).max(), last > 0 else { return [0] }
        if last < 3 { return Array(0...last) }
        let mid = last / 2
        return [0, mid, last]
    }

    private func xLabel(for index: Int) -> String {
        if let point = points.first(where: { $0.index == index }), let date = point.date {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: date)
        }
        return "\(index + 1)"
    }

    private func yLabel(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 1_000 {
            formatted = String(format: "%.1fK", absValue / 1_000)
        } else if absValue.rounded() == absValue {
            formatted = "\(Int(absValue))"
        } else {
            formatted = String(format: "%.0f", absValue)
        }
        return value < 0 ? "-$\(formatted)" : "$\(formatted)"
    }
}
