import SwiftUI

/// TraxPro gate surface — routes to in-app subscription purchase, never web checkout.
struct TraxProMembershipInfoView: View {
    let onClose: () -> Void
    var onViewSubscription: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var isPaidCommerceEnabled: Bool {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled
    }

    var body: some View {
        List {
            Section {
                if isPaidCommerceEnabled {
                    SettingsIntroBlock(
                        title: TraxProFeatureMessaging.featureTitle,
                        message: TraxProFeatureMessaging.featureRequired
                    )
                } else {
                    SettingsIntroBlock(
                        title: "Included with TradeTraxs",
                        message: "This version of TradeTraxs includes the full journal experience at no additional cost."
                    )
                }
            } footer: {
                if isPaidCommerceEnabled {
                    Text("TraxPro unlocks Trade AI, higher limits, and advanced analytics.")
                }
            }

            if isPaidCommerceEnabled, let onViewSubscription {
                Section {
                    Button(action: onViewSubscription) {
                        SettingsPrimaryActionLabel(
                            title: "View TraxPro Plans",
                            systemImage: "creditcard"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("traxpro.membership.viewPlans")
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("TraxPro")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("traxpro.membership.info")
    }
}
