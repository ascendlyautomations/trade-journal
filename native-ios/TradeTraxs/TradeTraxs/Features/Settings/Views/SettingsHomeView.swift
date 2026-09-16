import SwiftUI

struct SettingsHomeView: View {
    let authenticationCoordinator: AuthenticationCoordinator

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors
    @Bindable private var launchController = AppLaunchController.shared
    @State private var confirmsLogout = false

    var body: some View {
        List {
            if launchController.isDemoExperienceActive {
                Section {
                    Button {
                        launchController.exitDemoExplore(authIntent: .createAccount)
                    } label: {
                        SettingsNavigationRow(
                            title: "Create Account",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)
                    Button {
                        launchController.exitDemoExplore()
                    } label: {
                        SettingsNavigationRow(
                            title: "Exit Demo",
                            systemImage: "arrow.backward.circle",
                            isDestructive: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.exitDemo")
                } header: {
                    Text("Demo Mode")
                }
            }

            ForEach(SettingsHomeModel.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            ExperienceHaptics.play(.selection)
                            stackNavigation?.pushSettings(item.route)
                        } label: {
                            SettingsNavigationRow(
                                title: item.rowTitle,
                                systemImage: item.systemImage
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.row.\(item.route.rawValue)")
                    }
                } header: {
                    Text(section.title)
                }
            }

            if !launchController.isDemoExperienceActive {
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
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(ExperienceSpacing.xxs)
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
}
