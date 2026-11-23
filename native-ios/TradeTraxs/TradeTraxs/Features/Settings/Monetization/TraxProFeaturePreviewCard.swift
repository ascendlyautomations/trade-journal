import SwiftUI

/// Compact dashboard/settings upgrade preview for verified Free users.
struct TraxProFeaturePreviewCard: View {
    let title: String
    let message: String
    let feature: ProFeatureKind
    var accessibilityIdentifier: String

    @Environment(\.themeColors) private var colors

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }

    private var showsInteractivePreview: Bool {
        TraxsProPreviewCatalog.supportsInteractivePreview(for: feature)
            && TraxsProPreviewCoordinator.shared.canPresentPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .multilineTextAlignment(.leading)
            }
            Text(message)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if showsInteractivePreview,
               let previewFeature = TraxsProPreviewCatalog.previewFeature(for: feature)
            {
                Button {
                    ExperienceHaptics.play(.selection)
                    TraxsProPreviewCoordinator.shared.presentPreview(
                        feature: previewFeature,
                        entryPoint: .featurePreviewCard
                    )
                } label: {
                    Text(MonetizationPlanCopy.previewWithSampleDataButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("\(accessibilityIdentifier).preview")
            }

            if canPresentPaywall {
                Button {
                    ExperienceHaptics.play(.selection)
                    ProUpgradeCoordinator.shared.present(reason: .feature(feature))
                } label: {
                    Text("Explore \(MonetizationPlanCopy.proPlanName)")
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
                .accessibilityIdentifier("\(accessibilityIdentifier).upgrade")
            } else if IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
                Text(
                    "TraxsPro upgrades aren't available in this build yet. "
                        + "Check back soon or contact support if you already subscribe."
                )
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("\(accessibilityIdentifier).unavailable")
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}