import Charts
import SwiftUI

/// Cumulative withdrawals over time — reuses TradeTraxs equity curve styling.
struct PayoutEquityCurveView: View {
    let points: [PayoutEquityCurvePoint]
    let totalWithdrawals: Decimal
    var hasWithdrawals: Bool

    @Environment(\.themeColors) private var colors
    @State private var selectedIndex: Int?

    private let chartHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Payout Equity Curve")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Text("\(ProfileDisplay.formatMoney(totalWithdrawals)) Total")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fontWeight(.semibold)
            }

            Group {
                if hasWithdrawals, points.count >= 2 {
                    chart
                        .frame(height: chartHeight)
                } else {
                    emptyChartBody
                        .frame(height: chartHeight)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .accessibilityIdentifier("withdrawals.equityCurve")
    }

    private var emptyChartBody: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Text(ProfileDisplay.formatMoney(0))
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text("Your payout progress will appear here after your first withdrawal.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        let equityPoints = PayoutEquityCurveSupport.chartEquityPoints(from: points)
        return Chart {
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Payout", point.index),
                    y: .value("Withdrawn", point.cumulativeValue)
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

                AreaMark(
                    x: .value("Payout", point.index),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Withdrawn", point.cumulativeValue)
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
                    y: .value("Withdrawn", selected.cumulativeValue)
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
                        Text(xLabel(for: index, equityPoints: equityPoints))
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
                        Text(NumberDisplay.compactEquityAxis(raw))
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(colors.tertiaryText)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedIndex)
        .chartPlotStyle { plotArea in
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
                                max(plotFrame.minX + 88, plotFrame.minX + xPos),
                                plotFrame.maxX - 88
                            ),
                            y: plotFrame.minY + 36
                        )
                }
            }
        }
    }

    private func overlayCard(for point: RenderPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dateLabel = point.dateLabel {
                Text(dateLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(colors.secondaryText)
            }
            if let amount = point.eventAmount {
                Text("Payout: \(ProfileDisplay.formatMoney(amount))")
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            Text("Total Withdrawn: \(ProfileDisplay.formatMoney(point.cumulative))")
                .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(colors.profit)
            if let source = point.sourceLabel {
                Text(source)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
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
    }

    private struct RenderPoint: Identifiable {
        var id: Int { index }
        var index: Int
        var cumulative: Decimal
        var cumulativeValue: Double
        var date: Date?
        var eventAmount: Decimal?
        var sourceLabel: String?

        var dateLabel: String? {
            guard let date else { return nil }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private var chartPoints: [RenderPoint] {
        points.map {
            RenderPoint(
                index: $0.index,
                cumulative: $0.cumulative,
                cumulativeValue: NSDecimalNumber(decimal: $0.cumulative).doubleValue,
                date: $0.date,
                eventAmount: $0.eventAmount,
                sourceLabel: $0.sourceLabel
            )
        }
    }

    private var selected: RenderPoint? {
        guard let selectedIndex else { return nil }
        return chartPoints.first { $0.index == selectedIndex }
    }

    private var xDomain: ClosedRange<Int> {
        let maxIndex = points.map(\.index).max() ?? 1
        return 0...max(1, maxIndex)
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.cumulativeValue)
        let minY = min(values.min() ?? 0, 0)
        let maxY = values.max() ?? 0
        if minY == maxY {
            let pad = max(abs(maxY) * 0.1, 10)
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

    private func xLabel(for index: Int, equityPoints: [ProfileStatisticsMetrics.EquityPoint]) -> String {
        if let point = equityPoints.first(where: { $0.index == index }), let date = point.date {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: date)
        }
        return index == 0 ? "Start" : "\(index)"
    }
}
