import SwiftUI

struct SettingsHomeView: View {
    let authenticationCoordinator: AuthenticationCoordinator

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var launchController = AppLaunchController.shared
    @State private var confirmsLogout = false
    #if DEBUG
    @State private var clipCacheClearConfirmation = false
    @State private var isClearingClipVideoCache = false
    #endif

    var body: some View {
        ScrollViewReader { tourProxy in
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
                        .modifier(SettingsAppearanceTourTarget(isAppearance: item.route == .appearance))
                    }
                    if section.id == "personal" {
                        Button {
                            ExperienceHaptics.play(.selection)
                            appEnvironment.navigation.coordinator.selectTab(.home)
                            appEnvironment.navigation.coordinator.popToRoot(.home)
                            ContextualTourCoordinator.shared.beginReplay()
                        } label: {
                            SettingsNavigationRow(
                                title: "App Walkthrough",
                                systemImage: "play.circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.row.appWalkthrough")
                    }
                } header: {
                    Text(section.title)
                }
            }

            #if DEBUG
            if !launchController.isDemoExperienceActive {
                Section {
                    Button {
                        isClearingClipVideoCache = true
                        Task {
                            await ClipVideoDeliveryDebugControls.clearClipVideoCache()
                            isClearingClipVideoCache = false
                            clipCacheClearConfirmation = true
                        }
                    } label: {
                        SettingsNavigationRow(
                            title: "Clear Clip Video Cache",
                            systemImage: "externaldrive.badge.minus"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearingClipVideoCache)
                    .accessibilityIdentifier("settings.debug.clearClipVideoCache")
                    Button {
                        ContextualTourCoordinator.shared.resetStoredTourForDebug()
                    } label: {
                        SettingsNavigationRow(
                            title: "Reset App Tour",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.debug.resetAppTour")
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug only. Reset App Tour clears this account’s tour completion, then open Dashboard. Clear Clip Video Cache removes the Clip MP4 disk cache.")
                }
            }
            #endif

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
        .experienceDashboardGroupedRows()
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
        #if DEBUG
        .alert("Clip video cache cleared", isPresented: $clipCacheClearConfirmation) {
            Button("OK", role: .cancel) {}
        }
        #endif
        .accessibilityIdentifier("settings.home")
        .onChange(of: ContextualTourCoordinator.shared.scrollTarget) { _, target in
            guard let target else { return }
            if reduceMotion {
                tourProxy.scrollTo(target, anchor: .center)
            } else {
                withAnimation(ExperienceMotion.navigation) {
                    tourProxy.scrollTo(target, anchor: .center)
                }
            }
        }
        }
    }
}

/// Spotlight only the Appearance row. Other settings rows stay unchanged.
private struct SettingsAppearanceTourTarget: ViewModifier {
    let isAppearance: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAppearance {
            content.contextualTourTarget(.settingsAppearance)
        } else {
            content
        }
    }
}
