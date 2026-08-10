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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
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
}
