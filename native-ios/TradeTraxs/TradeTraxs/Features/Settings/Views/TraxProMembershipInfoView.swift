import SwiftUI

/// TraxPro gate surface — routes to in-app subscription purchase, never web checkout.
struct TraxProMembershipInfoView: View {
    let onClose: () -> Void
    var onViewSubscription: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                SettingsIntroBlock(
                    title: TraxProFeatureMessaging.featureTitle,
                    message: TraxProFeatureMessaging.featureRequired
                )
            } footer: {
                Text("TraxPro unlocks Trade AI, higher limits, and advanced analytics.")
            }

            if let onViewSubscription {
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
