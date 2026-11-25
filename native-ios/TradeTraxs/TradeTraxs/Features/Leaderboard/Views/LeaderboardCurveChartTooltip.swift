import SwiftUI

/// Compact, width-fixed tooltip for leaderboard curve scrubbing (all metrics / timeframes).
struct LeaderboardCurveChartTooltip: View {
    static let preferredWidth: CGFloat = 128
    static let horizontalEdgeInset: CGFloat = 6
    static let verticalOffset: CGFloat = 40

    let point: LeaderboardCurveChartPoint
    let prepared: LeaderboardCurveChartData.Prepared
    let category: LeaderboardCategory
    let metricFormat: LeaderboardCurveV1.MetricFormat
    let colors: SemanticColorPalette
    let dateText: String
    let valueText: (Double) -> String
    let seriesColor: (LeaderboardCurveSeries) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dateText)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)

            ForEach(LeaderboardCurveSeries.allCases, id: \.self) { series in
                if let value = prepared.plotValue(for: series, dayKey: point.dayKey) {
                    row(series: series, value: value)
                }
            }
        }
        .frame(width: Self.preferredWidth, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: colors.backgroundPrimary.opacity(0.25), radius: 6, y: 2)
        .accessibilityIdentifier("leaderboard.curve.tooltip")
    }

    private func row(series: LeaderboardCurveSeries, value: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(seriesColor(series))
                .frame(width: 4, height: 4)

            Text(compactSeriesTitle(series))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(colors.secondaryText)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)

            Text(valueText(value))
                .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(seriesColor(series))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(-1)
        }
    }

    private func compactSeriesTitle(_ series: LeaderboardCurveSeries) -> String {
        switch series {
        case .highest: return "High"
        case .you: return "You"
        case .average: return "Avg"
        case .lowest: return "Low"
        }
    }
}

enum LeaderboardCurveTooltipPlacement {
    /// Clamps tooltip center X so the full width stays inside `[containerMinX, containerMaxX]`.
    static func clampedCenterX(
        anchorX: CGFloat,
        containerMinX: CGFloat,
        containerMaxX: CGFloat,
        tooltipWidth: CGFloat = LeaderboardCurveChartTooltip.preferredWidth,
        edgeInset: CGFloat = LeaderboardCurveChartTooltip.horizontalEdgeInset
    ) -> CGFloat {
        let half = tooltipWidth / 2
        let minCenter = containerMinX + edgeInset + half
        let maxCenter = containerMaxX - edgeInset - half
        guard minCenter <= maxCenter else {
            return (containerMinX + containerMaxX) / 2
        }
        return min(max(anchorX, minCenter), maxCenter)
    }
}

enum LeaderboardCurveTooltipFormatting {
    nonisolated static func format(
        _ value: Double,
        category: LeaderboardCategory,
        metricFormat: LeaderboardCurveV1.MetricFormat
    ) -> String {
        if category.curveUsesIntegerAxis {
            let intVal = Int(value.rounded())
            if abs(intVal) >= 10_000 {
                return NumberDisplay.compactCount(intVal)
            }
            return NumberDisplay.integer(intVal)
        }
        switch metricFormat {
        case .currency:
            if abs(value) >= 1_000 {
                return NumberDisplay.chartSignedCurrency(value)
            }
            return NumberDisplay.chartCurrency(value)
        case .percent:
            if category == .winRate {
                return NumberDisplay.percent(
                    value * 100,
                    minimumFractionDigits: 0,
                    maximumFractionDigits: 1
                )
            }
            let absPercent = abs(value)
            if absPercent >= 100 {
                return NumberDisplay.percent(value, minimumFractionDigits: 0, maximumFractionDigits: 0)
            }
            return NumberDisplay.percent(value, minimumFractionDigits: 1, maximumFractionDigits: 1)
        case .ratio:
            if category == .winStreak || category == .followers {
                let intVal = Int(value.rounded())
                return abs(intVal) >= 10_000
                    ? NumberDisplay.compactCount(intVal)
                    : NumberDisplay.integer(intVal)
            }
            return NumberDisplay.ratio(Decimal(value), fractionDigits: 2)
        }
    }
}