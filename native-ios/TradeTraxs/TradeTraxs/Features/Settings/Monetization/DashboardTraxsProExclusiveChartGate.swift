import SwiftUI

/// In-chart upgrade surface for TraxsPro-exclusive dashboard analytics (verified Free tier).
struct DashboardTraxsProExclusiveChartGate: View {
    let message: String
    let accessibilityRootID: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
                Text("TraxsPro")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fontWeight(.semibold)
            }
            Text(message)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                feature: .premiumAnalytics,
                previewEntryPoint: .dashboardGate,
                previewAccessibilityIdentifier: "\(accessibilityRootID).preview",
                unlockAccessibilityIdentifier: "\(accessibilityRootID).upgrade"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityRootID)
    }
}