import SwiftUI

/// Root application chrome: Splash → Auth stack ↔ retained Main tabs + modal surface.
struct AppRootView: View {
    @Bindable var navigation: NavigationEnvironment
    @Bindable var themeManager: ThemeManager
    @Bindable var authenticationManager: AuthenticationManager
    let authenticationCoordinator: AuthenticationCoordinator
    let authenticationLifecycle: AuthenticationLifecycle
    @Bindable var currentUserProfile: CurrentUserProfileStore
    let allowsDevelopmentBypass: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var isLaunchBootstrapping = true

    var body: some View {
        Group {
            if isLaunchBootstrapping {
                SplashView()
            } else {
                switch navigation.store.sessionPhase {
                case .unauthenticated:
                    AuthInfrastructureView(
                        store: navigation.store,
                        coordinator: navigation.coordinator,
                        authenticationCoordinator: authenticationCoordinator,
                        authenticationManager: authenticationManager,
                        allowsDevelopmentBypass: allowsDevelopmentBypass
                    )
                case .authenticated:
                    MainTabShellView(
                        store: navigation.store,
                        coordinator: navigation.coordinator,
                        authenticationCoordinator: authenticationCoordinator,
                        currentUserProfile: currentUserProfile
                    )
                    .task {
                        currentUserProfile.loadIfNeeded()
                    }
                }
            }
        }
        .applyThemeEnvironment(themeManager.themeEnvironment)
        .experienceScreenBackground()
        .animation(
            ThemeAnimation.preferred(reduceMotion: reduceMotion),
            value: themeManager.selectedIdentifier
        )
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
            value: isLaunchBootstrapping
        )
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
            value: navigation.store.sessionPhase
        )
        .sheet(item: sheetBinding) { destination in
            sheetContent(destination)
                .applyThemeEnvironment(themeManager.themeEnvironment)
        }
        .fullScreenCover(item: fullScreenBinding) { destination in
            fullScreenContent(destination)
                .applyThemeEnvironment(themeManager.themeEnvironment)
        }
        .onAppear {
            themeManager.updateInterfaceStyle(colorScheme)
            Task {
                await authenticationLifecycle.applicationDidLaunch()
                ExperienceMotion.withAnimation(
                    ExperienceMotion.navigation,
                    reduceMotion: reduceMotion
                ) {
                    isLaunchBootstrapping = false
                }
            }
        }
        .onChange(of: colorScheme) { _, newStyle in
            themeManager.updateInterfaceStyle(newStyle)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                navigation.persistState()
                authenticationLifecycle.applicationDidEnterBackground()
            }
            if phase == .active {
                Task {
                    await authenticationLifecycle.applicationWillEnterForeground()
                }
            }
        }
        // Session-scoped caches (profile, Messages inbox, engagement, detail seeds)
        // are invalidated by ``AuthenticationCoordinator`` — not here.
        .onOpenURL { url in
            _ = navigation.deepLinkRouter.route(
                url: url,
                using: navigation.coordinator,
                store: navigation.store
            )
        }
        .environment(themeManager)
    }

    private var sheetBinding: Binding<SheetDestination?> {
        Binding(
            get: { navigation.store.presentedSheet },
            set: { navigation.store.presentedSheet = $0 }
        )
    }

    private var fullScreenBinding: Binding<FullScreenDestination?> {
        Binding(
            get: { navigation.store.presentedFullScreen },
            set: { navigation.store.presentedFullScreen = $0 }
        )
    }

    @ViewBuilder
    private func sheetContent(_ destination: SheetDestination) -> some View {
        NavigationStack {
            NavigationInfrastructurePlaceholder(
                title: sheetTitle(destination),
                subtitle: "Sheet infrastructure — \(destination.rawValue)",
                systemImage: "rectangle.bottomhalf.inset.filled"
            )
            .navigationTitle(sheetTitle(destination))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        navigation.coordinator.dismissSheet()
                    }
                }
                if destination == .composeChooser {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Trade") {
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.trade)
                        }
                    }
                }
            }
            .presentationDetents(detents(for: destination))
        }
    }

    @ViewBuilder
    private func fullScreenContent(_ destination: FullScreenDestination) -> some View {
        NavigationStack {
            Group {
                switch destination {
                case .storyViewer(let storyID):
                    FeedStoryViewerView(
                        storyID: storyID,
                        data: appEnvironment.data,
                        onClose: { navigation.coordinator.dismissFullScreen() }
                    )
                default:
                    NavigationInfrastructurePlaceholder(
                        title: fullScreenTitle(destination),
                        subtitle: "Full-screen cover infrastructure",
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }
            }
            .navigationTitle(fullScreenTitle(destination))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        navigation.coordinator.dismissFullScreen()
                    }
                }
            }
        }
    }

    private func detents(for destination: SheetDestination) -> Set<PresentationDetent> {
        switch destination {
        case .composeChooser, .quickTrade, .accountSwitcher:
            return [.medium, .large]
        default:
            return [.medium, .large]
        }
    }

    private func sheetTitle(_ destination: SheetDestination) -> String {
        switch destination {
        case .composeChooser: return "Create"
        case .quickTrade: return "Quick Trade"
        case .tradeFilters: return "Filters"
        case .comments: return "Comments"
        case .followList: return "Followers"
        case .shareToMessages: return "Share"
        case .accountSwitcher: return "Accounts"
        case .notificationPermission: return "Notifications"
        }
    }

    private func fullScreenTitle(_ destination: FullScreenDestination) -> String {
        switch destination {
        case .addTrade: return "Add Trade"
        case .importCSV: return "Import"
        case .importReview: return "Review Import"
        case .newPost: return "New Post"
        case .newReel: return "New Reel"
        case .newStory: return "New Story"
        case .upgrade: return "Upgrade"
        case .mediaViewer: return "Media"
        case .storyViewer: return "Story"
        }
    }
}
