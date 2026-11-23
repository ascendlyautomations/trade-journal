import SwiftUI

/// In-chart upgrade surface for TraxsPro-exclusive dashboard analytics (verified Free tier).
struct DashboardTraxsProExclusiveChartGate: View {
    let message: String
    let accessibilityRootID: String

    @Environment(\.themeColors) private var colors

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }

    private var showsInteractivePreview: Bool {
        TraxsProPreviewCatalog.supportsInteractivePreview(for: .premiumAnalytics)
            && TraxsProPreviewCoordinator.shared.canPresentPreview
    }

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

            if showsInteractivePreview {
                Button {
                    ExperienceHaptics.play(.selection)
                    TraxsProPreviewCoordinator.shared.presentDashboardPreview(entryPoint: .dashboardGate)
                } label: {
                    Text(MonetizationPlanCopy.previewWithSampleDataButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("\(accessibilityRootID).preview")
            }

            if canPresentPaywall {
                Button {
                    ExperienceHaptics.play(.selection)
                    ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
                } label: {
                    Text(MonetizationPlanCopy.exploreTraxsProButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .background(colors.accent, in: RoundedRectangle(
                            cornerRadius: ExperienceRadius.sm,
                            style: .continuous
                        ))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityRootID).upgrade")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityRootID)
    }
}