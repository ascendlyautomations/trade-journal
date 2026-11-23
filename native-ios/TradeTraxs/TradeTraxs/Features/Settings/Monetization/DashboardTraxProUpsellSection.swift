import SwiftUI

/// Single consolidated TraxsPro upsell at the bottom of the Home dashboard.
struct DashboardTraxProUpsellSection: View {
    let presentation: ProPremiumFeaturePresentation
    var profileID: ProfileID?
    var onRetryEntitlementVerification: () -> Void

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
        Group {
            switch presentation {
            case .unrestricted:
                EmptyView()
            case .verifyingEntitlement:
                TraxProEntitlementVerificationInlineCard(
                    profileID: profileID,
                    onRetry: onRetryEntitlementVerification,
                    accessibilityIdentifier: "dashboard.traxpro.entitlement.verification"
                )
            case .lockedPreview:
                lockedContent
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.traxpro.upsell")
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            MonetizationPlanPresentation.ProMarketingHeader(
                title: MonetizationPlanCopy.dashboardHeadline,
                subtitle: MonetizationPlanCopy.dashboardSubtitle
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(MonetizationPlanCopy.dashboardPremiumPreviewTitle)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(MonetizationPlanCopy.dashboardPremiumPreviewMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                MonetizationPlanPresentation.DashboardPremiumAnalyticsOverviewList(
                    compact: true,
                    showsDividers: true
                )
            }

            if showsInteractivePreview {
                Button {
                    ExperienceHaptics.play(.selection)
                    TraxsProPreviewCoordinator.shared.presentDashboardPreview(entryPoint: .dashboardUpsell)
                } label: {
                    Text(MonetizationPlanCopy.previewWithSampleDataButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("dashboard.traxpro.preview")
            }

            if canPresentPaywall {
                Button {
                    ExperienceHaptics.play(.selection)
                    ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
                } label: {
                    Text(MonetizationPlanCopy.exploreTraxsProButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, ExperienceSpacing.xxs)
                .accessibilityIdentifier("dashboard.traxpro.upgrade")
            } else if IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
                Text(
                    "TraxsPro upgrades aren't available in this build yet. "
                        + "Check back soon or contact support if you already subscribe."
                )
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard.traxpro.unavailable")
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
    }
}