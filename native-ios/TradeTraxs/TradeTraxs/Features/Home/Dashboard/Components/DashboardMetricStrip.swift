import SwiftUI

enum DashboardMetricStripLayout: Equatable {
    case horizontalStrip
    case gridTwoByTwo
}

/// Compact glanceable KPI row, one metric system, no oversized cards.
struct DashboardMetricStrip: View {
    let chips: [DashboardMetricChip]
    var layout: DashboardMetricStripLayout = .horizontalStrip

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var numbersReady = false

    var body: some View {
        Group {
            switch layout {
            case .horizontalStrip:
                horizontalStrip
            case .gridTwoByTwo:
                twoByTwoGrid
            }
        }
        .padding(.vertical, ExperienceSpacing.sm)
        .padding(.horizontal, ExperienceSpacing.xs)
        .experienceDashboardCard(prominence: .standard)
        .padding(.horizontal, ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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

    private var horizontalStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                kpiCell(chip)
                if index < chips.count - 1 {
                    verticalRule
                }
            }
        }
    }

    private var twoByTwoGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let first = chips[safe: 0] { kpiCell(first) }
                if chips.count > 1 {
                    verticalRule
                    if let second = chips[safe: 1] { kpiCell(second) }
                }
            }
            if chips.count > 2 {
                horizontalRule
                HStack(spacing: 0) {
                    if let third = chips[safe: 2] { kpiCell(third) }
                    if chips.count > 3 {
                        verticalRule
                        if let fourth = chips[safe: 3] { kpiCell(fourth) }
                    }
                }
            }
        }
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(width: ExperienceBorder.hairline)
            .padding(.vertical, ExperienceSpacing.xs)
    }

    private var horizontalRule: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(height: ExperienceBorder.hairline)
            .padding(.horizontal, ExperienceSpacing.xs)
    }

    private func kpiCell(_ chip: DashboardMetricChip) -> some View {
        VStack(spacing: 3) {
            Text(chip.label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(numbersReady ? chip.value : "–")
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}