import SwiftUI

/// Locked TraxsPro psychology analytics (insights, coach, advanced comparisons).
struct PsychologyAnalyticsPremiumLockedSection: View {
    @Environment(\.themeColors) private var colors

    private let locks: [(title: String, detail: String)] = [
        ("Psychology insights", "Compare check-in patterns to win rate and P&L on matched days."),
        ("Advanced analytics", "Sleep, stress, discipline, and emotion splits with both sides of each comparison."),
        ("Psychology Coach", "Daily recommendations based on your analytics and check-ins."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Included with TraxsPro")
                .experienceStyle(.headline, color: colors.primaryText)

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(locks, id: \.title) { item in
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(colors.tertiaryText)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.primaryText)
                            Text(item.detail)
                                .experienceStyle(.caption2, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                feature: .premiumAnalytics,
                previewEntryPoint: .dashboardGate,
                previewAccessibilityIdentifier: "psychologyAnalytics.preview",
                unlockAccessibilityIdentifier: "psychologyAnalytics.exploreTraxsPro"
            )
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.lg)
        .accessibilityIdentifier("psychologyAnalytics.lockedSection")
    }
}