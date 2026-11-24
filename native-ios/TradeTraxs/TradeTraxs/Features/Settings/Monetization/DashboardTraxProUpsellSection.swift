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

            MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                feature: .premiumAnalytics,
                previewEntryPoint: .dashboardUpsell,
                previewAccessibilityIdentifier: "dashboard.traxpro.preview",
                unlockAccessibilityIdentifier: "dashboard.traxpro.upgrade"
            )

            if !canPresentPaywall, IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
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