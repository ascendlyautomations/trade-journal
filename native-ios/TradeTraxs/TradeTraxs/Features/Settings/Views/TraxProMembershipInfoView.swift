import SwiftUI

/// Informational TraxPro surface — no purchase or external billing links.
struct TraxProMembershipInfoView: View {
    let onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                SettingsIntroBlock(
                    title: TraxProFeatureMessaging.featureTitle,
                    message: TraxProFeatureMessaging.featureRequired
                )
            } footer: {
                Text("TraxPro access is tied to your account membership status.")
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
