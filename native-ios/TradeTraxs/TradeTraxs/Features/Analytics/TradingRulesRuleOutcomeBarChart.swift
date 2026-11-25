import Charts
import SwiftUI

/// Compact Followed vs Violated trade count chart (rule detail).
struct TradingRulesRuleOutcomeBarChart: View {
    let followedCount: Int
    let violatedCount: Int

    @Environment(\.themeColors) private var colors

    private struct Bucket: Identifiable {
        var id: String
        var title: String
        var count: Int
        var tone: Color
        var percent: Int
    }

    private var total: Int { followedCount + violatedCount }

    private var buckets: [Bucket] {
        guard total > 0 else { return [] }
        return [
            Bucket(
                id: "followed",
                title: "Followed",
                count: followedCount,
                tone: colors.profit,
                percent: Int((Double(followedCount) / Double(total) * 100).rounded())
            ),
            Bucket(
                id: "violated",
                title: "Violated",
                count: violatedCount,
                tone: colors.loss,
                percent: Int((Double(violatedCount) / Double(total) * 100).rounded())
            ),
        ]
    }

    var body: some View {
        Group {
            if total == 0 {
                DashboardChartEmptyCopy(
                    message: "No trade-level outcomes for this rule in the current scope."
                )
            } else {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    Chart(buckets) { bucket in
                        BarMark(
                            x: .value("Outcome", bucket.title),
                            y: .value("Trades", bucket.count)
                        )
                        .foregroundStyle(bucket.tone)
                        .cornerRadius(4)
                        .annotation(position: .top, spacing: 4) {
                            Text("\(bucket.percent)%")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(colors.primaryText)
                        }
                    }
                    .chartYScale(domain: 0 ... max(max(followedCount, violatedCount), 1))
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(colors.divider.opacity(0.55))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(preset: .aligned) { value in
                            AxisValueLabel(centered: true) {
                                if let title = value.as(String.self) {
                                    Text(title)
                                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(colors.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(height: 132)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Followed and violated trades")
                    .accessibilityValue(accessibilitySummary)

                    HStack(spacing: ExperienceSpacing.md) {
                        legendItem(
                            title: "Followed",
                            count: followedCount,
                            tone: colors.profit
                        )
                        legendItem(
                            title: "Violated",
                            count: violatedCount,
                            tone: colors.loss
                        )
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        guard total > 0 else { return "No trades." }
        return "\(followedCount) followed, \(violatedCount) violated, \(total) total trades."
    }

    private func legendItem(title: String, count: Int, tone: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
            Text("\(title) · \(NumberDisplay.integer(count))")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(colors.secondaryText)
        }
    }
}