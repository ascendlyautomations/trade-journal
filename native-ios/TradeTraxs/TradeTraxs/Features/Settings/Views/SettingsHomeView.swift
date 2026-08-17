import SwiftUI

struct SettingsHomeView: View {
    let navigationCoordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator

    @Environment(\.themeColors) private var colors
    @State private var confirmsLogout = false

    var body: some View {
        List {
            ForEach(SettingsHomeModel.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.open(.profile(.settings(item.route)))
                        } label: {
                            SettingsNavigationRow(
                                title: item.route.title,
                                subtitle: item.subtitle,
                                systemImage: item.systemImage
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let footer = sectionFooter(for: section.id) {
                        Text(footer)
                    }
                }
            }

            Section {
                Button {
                    confirmsLogout = true
                } label: {
                    SettingsNavigationRow(
                        title: "Log Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.logout")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Settings")
        .confirmationDialog(
            "Log out of TradeTraxs?",
            isPresented: $confirmsLogout,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                ExperienceHaptics.play(.selection)
                Task { await authenticationCoordinator.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("settings.home")
    }

    private func sectionFooter(for sectionID: String) -> String? {
        switch sectionID {
        case "preferences":
            return "Choose which notifications you’d like to receive."
        case "tradetraxs":
            return "Membership, accounts, and referrals."
        case "privacy":
            return "Control what other traders can see."
        case "support":
            return "Help, feedback, and app information."
        case "legal":
            return "Policies that apply to your use of TradeTraxs."
        default:
            return nil
        }
    }
}
