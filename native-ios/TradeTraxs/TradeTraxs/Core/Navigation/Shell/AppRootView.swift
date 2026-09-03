import SwiftUI

/// Root application chrome: Splash → Auth stack ↔ retained Main tabs + modal surface.
struct AppRootView: View {
    @Bindable var navigation: NavigationEnvironment
    @Bindable var themeManager: ThemeManager
    @Bindable var authenticationManager: AuthenticationManager
    let authenticationCoordinator: AuthenticationCoordinator
    @Bindable var authenticationLifecycle: AuthenticationLifecycle
    @Bindable var currentUserProfile: CurrentUserProfileStore
    @Bindable var appBootstrapState: AppBootstrapState
    @Bindable var profileOnboardingGate: ProfileOnboardingGateStore
    let allowsDevelopmentBypass: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var isLaunchBootstrapping = true

    var body: some View {
        Group {
            authRootContent
        }
        .applyThemeEnvironment(themeManager.themeEnvironment)
        // Root fill only — do not also apply bar chrome here (owned by MainTabShellView)
        // so safe-area insets are not compensated twice.
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
            NavigationCoordinatorProxy.openManageAccounts = {
                navigation.coordinator.pushHome(.settings(.tradingAccounts))
            }
            if authenticationLifecycle.initialRestoreCompleted {
                isLaunchBootstrapping = false
            }
            Task {
                await authenticationLifecycle.applicationDidLaunch()
            }
        }
        .onChange(of: authenticationManager.state) { _, newState in
            authenticationCoordinator.syncNavigation(with: newState)
        }
        .onChange(of: authenticationLifecycle.initialRestoreCompleted) { _, completed in
            if completed {
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
                    appEnvironment.data.realtimeHub.resumeIfNeeded()
                    GettingStartedStore.shared.onForeground()
                }
            }
        }
        // Session-scoped caches (profile, Messages inbox, engagement, detail seeds)
        // are invalidated by ``AuthenticationCoordinator`` — not here.
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleIncomingURL(url)
        }
        .ownerAccountFilterDropdownOverlay()
        .onChange(of: navigation.store.selectedTab) { _, _ in
            OwnerAccountFilterDropdownController.shared.dismiss()
        }
        .environment(themeManager)
    }

    @ViewBuilder
    private var authRootContent: some View {
        switch authenticationManager.state {
        case .unknown, .refreshing:
            if authenticationManager.isValidationRetryInFlight {
                sessionValidationSurface(isRetrying: true)
            } else {
                SplashView()
            }

        case .sessionValidationFailed:
            sessionValidationSurface(isRetrying: false)

        case .authenticated, .locked:
            if navigation.store.sessionPhase == .authenticated, authenticationManager.state.isSessionReady {
                authenticatedShell
            } else {
                SplashView()
            }

        case .unauthenticated, .failure:
            if isLaunchBootstrapping {
                SplashView()
            } else {
                AuthInfrastructureView(
                    store: navigation.store,
                    coordinator: navigation.coordinator,
                    authenticationCoordinator: authenticationCoordinator,
                    authenticationManager: authenticationManager,
                    allowsDevelopmentBypass: allowsDevelopmentBypass
                )
            }

        case .authenticating:
            AuthInfrastructureView(
                store: navigation.store,
                coordinator: navigation.coordinator,
                authenticationCoordinator: authenticationCoordinator,
                authenticationManager: authenticationManager,
                allowsDevelopmentBypass: allowsDevelopmentBypass
            )
        }
    }

    private var authenticatedShell: some View {
        Group {
            switch profileOnboardingGate.phase {
            case .idle, .resolving:
                SplashView()
                    .task(id: authenticationManager.restorationGeneration) {
                        guard authenticationManager.state.isSessionReady else { return }
                        profileOnboardingGate.resolveIfNeeded()
                    }

            case .required(let snapshot):
                ProfileOnboardingView(
                    viewModel: ProfileOnboardingViewModel(
                        snapshot: snapshot,
                        profiles: appEnvironment.data.profiles,
                        gateStore: profileOnboardingGate,
                        uploadService: appEnvironment.data.uploadService,
                        objectStorage: appEnvironment.data.objectStorage,
                        appConfiguration: appEnvironment.configuration
                    )
                )

            case .complete:
                mainAuthenticatedShell

            case .failed(let message):
                SessionValidationView(
                    message: message,
                    isRetrying: false,
                    onRetry: {
                        profileOnboardingGate.resolveIfNeeded(forceNetwork: true)
                    },
                    onSignIn: {
                        Task { await authenticationCoordinator.logout() }
                    }
                )
            }
        }
    }

    private var mainAuthenticatedShell: some View {
        MainTabShellView(
            store: navigation.store,
            coordinator: navigation.coordinator,
            authenticationCoordinator: authenticationCoordinator,
            currentUserProfile: currentUserProfile
        )
        .task(id: authenticationManager.restorationGeneration) {
            guard authenticationManager.state.isSessionReady else { return }
            await authenticationManager.awaitNetworkReady()
            guard authenticationManager.state.isSessionReady else { return }
            appBootstrapState.markReady()
            AuthFlowTracer.trace("bootstrap.shell.ready", phase: .authenticated)
            if !currentUserProfile.hasLoadedContent {
                currentUserProfile.loadIfNeeded()
            } else {
                currentUserProfile.ensureTabAvatarLoaded()
            }
        }
        .onChange(of: currentUserProfile.phase) { _, phase in
            switch phase {
            case .loaded:
                AuthFlowTracer.trace("bootstrap.profile.completed", phase: .authenticated)
            case .failed:
                AuthFlowTracer.trace("bootstrap.profile.failed", phase: .bootstrapFailed)
            case .loading, .idle:
                break
            }
        }
    }

    private func sessionValidationSurface(isRetrying: Bool) -> some View {
        SessionValidationView(
            message: sessionValidationMessage,
            isRetrying: isRetrying,
            onRetry: {
                Task { await authenticationCoordinator.retrySessionValidation() }
            },
            onSignIn: {
                Task { await authenticationCoordinator.logout() }
            }
        )
    }

    private var sessionValidationMessage: String {
        guard let error = authenticationManager.lastSessionValidationError else {
            return "Check your connection and try again, or sign in again."
        }
        if error.isTransientRefreshFailure {
            switch error {
            case .unknown(let reason) where reason == "networkUnavailable":
                return "You're offline. Connect to the internet and try again."
            case .unknown(let reason) where reason == "serverUnavailable":
                return "Our servers are temporarily unavailable. Try again shortly."
            default:
                return "We couldn't reach the server. Try again or sign in again."
            }
        }
        return "Your session could not be restored. Sign in again to continue."
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
            Group {
                switch destination {
                case .composeChooser:
                    ComposeChooserView(
                        onAddTrade: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.trade)
                        },
                        onCreatePost: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.post)
                        },
                        onCreateReel: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.reel)
                        },
                        onCreateAchievement: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.achievement)
                        },
                        onCreateStory: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.story)
                        },
                        onClose: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                        }
                    )
                case .dailyCheckIn:
                    DailyCheckInView(
                        data: appEnvironment.data,
                        onClose: { navigation.coordinator.dismissSheet() },
                        onOpenHistory: {
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.open(.home(.checkInHistory))
                        }
                    )
                default:
                    NavigationInfrastructurePlaceholder(
                        title: sheetTitle(destination),
                        subtitle: "Sheet infrastructure — \(destination.rawValue)",
                        systemImage: "rectangle.bottomhalf.inset.filled"
                    )
                    .experienceNavigationTitle(sheetTitle(destination))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                navigation.coordinator.dismissSheet()
                            }
                        }
                    }
                }
            }
            .experienceSheetChrome(detents: detents(for: destination))
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
                case .addTrade:
                    TradeEntryHubView(
                        data: appEnvironment.data,
                        initialTab: .manual,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .editTrade(let tradeID):
                    AddTradeView(
                        data: appEnvironment.data,
                        mode: .edit(tradeID),
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .newPost:
                    CreatePostView(
                        data: appEnvironment.data,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .newAchievement:
                    CreateAchievementView(
                        data: appEnvironment.data,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .newReel:
                    CreateReelView(
                        data: appEnvironment.data,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .newStory:
                    CreateStoryView(
                        data: appEnvironment.data,
                        onPublished: { story in
                            navigation.coordinator.dismissFullScreen()
                            navigation.coordinator.present(fullScreen: .storyViewer(story.id))
                        },
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .importCSV:
                    TradeEntryHubView(
                        data: appEnvironment.data,
                        initialTab: .importTrades,
                        initialImportChannel: .csv,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                default:
                    NavigationInfrastructurePlaceholder(
                        title: fullScreenTitle(destination),
                        subtitle: "Full-screen cover infrastructure",
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                    .experienceNavigationTitle(fullScreenTitle(destination))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                navigation.coordinator.dismissFullScreen()
                            }
                        }
                    }
                }
            }
        }
    }

    private func detents(for destination: SheetDestination) -> Set<PresentationDetent> {
        switch destination {
        case .composeChooser, .quickTrade, .accountSwitcher, .dailyCheckIn:
            return [.medium, .large]
        default:
            return [.medium, .large]
        }
    }

    private func handleIncomingURL(_ url: URL) {
        _ = navigation.deepLinkRouter.route(
            url: url,
            using: navigation.coordinator,
            store: navigation.store
        )
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
        case .dailyCheckIn: return "Daily Check-In"
        }
    }

    private func fullScreenTitle(_ destination: FullScreenDestination) -> String {
        switch destination {
        case .addTrade: return "Add Trade"
        case .editTrade: return "Edit Trade"
        case .importCSV: return "Import"
        case .importReview: return "Review Import"
        case .newPost: return "New Post"
        case .newAchievement: return "New Achievement"
        case .newReel: return "New Clip"
        case .newStory: return "New Story"
        case .upgrade: return "Upgrade"
        case .mediaViewer: return "Media"
        case .storyViewer: return "Story"
        }
    }
}
