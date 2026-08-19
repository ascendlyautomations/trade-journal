import SwiftUI

/// Compact glanceable KPI row — one metric system, no oversized cards.
struct DashboardMetricStrip: View {
    let chips: [DashboardMetricChip]

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var numbersReady = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                kpiCell(chip)
                if index < chips.count - 1 {
                    Rectangle()
                        .fill(colors.border.opacity(0.45))
                        .frame(width: ExperienceBorder.hairline)
                        .padding(.vertical, ExperienceSpacing.xs)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.sm)
        .padding(.horizontal, ExperienceSpacing.xs)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .padding(.horizontal, ExperienceSpacing.md)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: numbersReady
        )
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: chips.map(\.value)
        )
        .onAppear {
            guard !numbersReady else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                numbersReady = true
            }
        }
        .accessibilityIdentifier("dashboard.metrics")
    }

    private func kpiCell(_ chip: DashboardMetricChip) -> some View {
        VStack(spacing: 3) {
            Text(chip.label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(numbersReady ? chip.value : "—")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(chip.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.metric.\(chip.id)")
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
