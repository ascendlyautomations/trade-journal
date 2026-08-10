import SwiftUI

/// Large Stocks-style equity curve — reuses ``ProfileEquityCurveView``.
struct DashboardEquityHero: View {
    let summary: DashboardChartMetrics.Summary

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equity")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                    Text(DashboardViewModel.money(summary.currentEquity))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(summary.currentEquity >= 0 ? colors.profit : colors.loss)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(summary.tradeCount) trades")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            .padding(.horizontal, ExperienceSpacing.md)

            ProfileEquityCurveView(points: summary.equityData)
                .frame(height: 260)
                .padding(.horizontal, ExperienceSpacing.sm)
                .accessibilityLabel("Equity curve")
                .accessibilityHint("Drag to inspect date and equity")
        }
        .padding(.vertical, ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
            value: summary.equityData.count
        )
        .accessibilityIdentifier("dashboard.equity")
    }
}
