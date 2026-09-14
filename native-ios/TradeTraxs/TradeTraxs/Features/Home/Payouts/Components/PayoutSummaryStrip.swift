import SwiftUI

/// Compact payout totals — mirrors Dashboard metric strip density.
struct PayoutSummaryStrip: View {
    let total: Decimal
    let count: Int
    let average: Decimal?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 0) {
            metricCell(label: "Total Payouts", value: ProfileDisplay.formatMoney(total))
            divider
            metricCell(label: "Payouts", value: "\(count)")
            divider
            metricCell(
                label: "Average Payout",
                value: average.map { ProfileDisplay.formatMoney($0) } ?? "—"
            )
        }
        .padding(.vertical, ExperienceSpacing.sm)
        .padding(.horizontal, ExperienceSpacing.xs)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .accessibilityIdentifier("payouts.summary")
    }

    private var divider: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(width: ExperienceBorder.hairline)
            .padding(.vertical, ExperienceSpacing.xs)
    }

    private func metricCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.xs)
    }
}
