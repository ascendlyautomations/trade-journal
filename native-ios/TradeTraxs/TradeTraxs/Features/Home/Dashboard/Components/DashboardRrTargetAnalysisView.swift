import SwiftUI

struct DashboardRrTargetAnalysisView: View {
    let analysis: DashboardRrTargetAnalysis

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            if analysis.pairedCount == 0 {
                if let headline = analysis.headline {
                    Text(headline)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.medium)
                }
                if !analysis.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        ForEach(Array(analysis.bullets.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .experienceStyle(.subheadline, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(
                        "Only trades with both Targeted Risk/Reward and Max R:R Reached appear here. This is separate from realized profit and from the dashboard Avg Max R:R KPI."
                    )
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                }
            } else {
                if let summary = analysis.sampleSummary {
                    Text(summary)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    metricColumn(title: "Avg target R:R", value: analysis.avgTargetRr)
                    metricColumn(title: "Avg max reached", value: analysis.avgMaxRrReached)
                }

                if let attainment = analysis.avgTargetAttainmentRatio {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text("Target attainment %")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(attainmentText(attainment))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.accent)
                        Text(
                            "Max R:R reached ÷ targeted R:R on paired trades only. Can exceed 100% when price runs past target. Not realized P&L capture."
                        )
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let headline = analysis.headline {
                    Text(headline)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.medium)
                }

                if !analysis.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        ForEach(Array(analysis.bullets.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                                Circle()
                                    .fill(colors.accent.opacity(0.85))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(line)
                                    .experienceStyle(.subheadline, color: colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.rrTargeting")
    }

    @ViewBuilder
    private func metricColumn(title: String, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text(value.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "—")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attainmentText(_ ratio: Decimal) -> String {
        let pct = Int(truncating: NSDecimalNumber(decimal: ratio * 100))
        return "\(pct)%"
    }
}
