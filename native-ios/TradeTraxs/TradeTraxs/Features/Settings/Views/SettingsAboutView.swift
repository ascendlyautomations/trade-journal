import SwiftUI

struct SettingsAboutView: View {
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                SettingsInfoRow(title: "App", value: "TradeTraxs")
                SettingsInfoRow(title: "Version", value: version)
                SettingsInfoRow(title: "Build", value: build)
            }

            Section("Legal") {
                legalButton(.legalTerms)
                legalButton(.legalPrivacy)
                legalButton(.legalCommunityGuidelines)
                legalButton(.legalRefund)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .navigationTitle("About TradeTraxs")
        .accessibilityIdentifier("settings.about")
    }

    private func legalButton(_ route: SettingsRoute) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            navigationCoordinator.open(.profile(.settings(route)))
        } label: {
            SettingsNavigationRow(title: route.title, systemImage: "doc.text")
        }
        .buttonStyle(.plain)
    }
}
