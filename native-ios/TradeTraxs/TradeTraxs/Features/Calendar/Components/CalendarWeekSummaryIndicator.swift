import SwiftUI

/// Compact weekly P&L indicator aligned beneath each calendar week row.
struct CalendarWeekSummaryIndicator: View {
    let netPnL: Decimal

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Spacer(minLength: 0)
            Text("WEEK")
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(CalendarFormatting.compactPnL(netPnL))
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(
                    theme.metricColor(
                        for: NSDecimalNumber(decimal: netPnL).doubleValue
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, 1)
        .padding(.bottom, ExperienceSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(CalendarFormatting.compactPnL(netPnL))")
    }
}
