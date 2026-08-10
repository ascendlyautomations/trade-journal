import SwiftUI

struct DashboardInsightsSection: View {
    let insights: [DashboardInsightItem]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Insights")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .padding(.horizontal, ExperienceSpacing.md)

            if insights.isEmpty {
                Text("Add more trades to unlock personalized insights.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                            ExperienceIcon(icon: .sparkles, size: .sm, color: colors.accent)
                            Text(insight.body)
                                .experienceStyle(.callout, color: colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(ExperienceSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.fillSecondary.opacity(0.45), in: RoundedRectangle(
                            cornerRadius: ExperienceRadius.md,
                            style: .continuous
                        ))
                        .accessibilityIdentifier("dashboard.insight.\(insight.id)")
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("dashboard.insights")
    }
}
