import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                SettingsInfoRow(title: "App", value: "TradeTraxs")
                SettingsInfoRow(title: "Version", value: version)
            } footer: {
                Text("You’re using the TradeTraxs iOS app.")
            }

            Section("Legal") {
                legalButton(.legalTerms)
                legalButton(.legalPrivacy)
                legalButton(.legalCommunityGuidelines)
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .experienceNavigationTitle("About TradeTraxs")
        .accessibilityIdentifier("settings.about")
    }

    private func legalButton(_ route: SettingsRoute) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            stackNavigation?.pushSettings(route)
        } label: {
            SettingsNavigationRow(title: route.title, systemImage: "doc.text")
        }
        .buttonStyle(.plain)
    }
}
