import SwiftUI

/// Compact dashboard/settings upgrade preview for verified Free users.
struct TraxProFeaturePreviewCard: View {
    let title: String
    let message: String
    let feature: ProFeatureKind
    var showsActionButtons: Bool = true
    var previewFeature: TraxsProPreviewFeature? = nil
    var previewEntryPoint: TraxsProPreviewEntryPoint = .featurePreviewCard
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

            if showsActionButtons {
                MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                    feature: feature,
                    previewFeature: previewFeature,
                    previewEntryPoint: previewEntryPoint,
                    previewAccessibilityIdentifier: "\(accessibilityIdentifier).preview",
                    unlockAccessibilityIdentifier: "\(accessibilityIdentifier).upgrade"
                )

                if !canPresentPaywall,
                   !showsInteractivePreview,
                   IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled
                {
                    unavailableFootnote
                }
            } else if !canPresentPaywall, IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
                unavailableFootnote
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var unavailableFootnote: some View {
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