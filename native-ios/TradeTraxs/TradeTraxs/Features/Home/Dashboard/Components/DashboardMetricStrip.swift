import SwiftUI

/// Compact horizontal KPI chips — Net P&L, Win %, PF, etc.
struct DashboardMetricStrip: View {
    let chips: [DashboardMetricChip]

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.sm) {
                ForEach(chips) { chip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chip.label)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                        Text(chip.value)
                            .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(toneColor(chip.tone))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, ExperienceSpacing.sm)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .frame(minWidth: 96, alignment: .leading)
                    .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(
                        cornerRadius: ExperienceRadius.sm,
                        style: .continuous
                    ))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard.metric.\(chip.id)")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("dashboard.metrics")
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
