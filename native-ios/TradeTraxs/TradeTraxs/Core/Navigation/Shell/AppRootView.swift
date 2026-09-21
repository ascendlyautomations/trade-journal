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
    @Bindable var contentReportPresenter: ContentReportPresenter
    @Bindable var thirdPartyAIConsentPresenter: ThirdPartyAIConsentPresenter
    let allowsDevelopmentBypass: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable private var launchController = AppLaunchController.shared
    @State private var isLaunchBootstrapping = true

    var body: some View {
        Group {
            authRootContent
        }
        .onAppear { StartupTrace.event("rootBodyFirstEvaluation") }
        .applyThemeEnvironment(themeManager.themeEnvironment)
        // Root fill only — do not also apply bar chrome here (owned by MainTabShellView)
        // so safe-area insets are not compensated twice.
        .experienceScreenBackground()
        .experienceKeyboardDismissOnTapOutside()
        .experienceKeyboardDoneToolbar()
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
        .sheet(item: $contentReportPresenter.activeRequest) { request in
            ContentReportSheet(
                request: request,
                repository: appEnvironment.data.contentReports,
                onDismiss: { contentReportPresenter.dismiss() },
                onBlockUser: { profileID in
                    Task {
                        _ = try? await UserBlockCoordinator.shared.setBlocked(
                            otherID: profileID,
                            conversationID: nil,
                            blocked: true,
                            messages: appEnvironment.data.messages
                        )
                    }
                }
            )
            .applyThemeEnvironment(themeManager.themeEnvironment)
        }
        .sheet(isPresented: $thirdPartyAIConsentPresenter.isPresented, onDismiss: {
            thirdPartyAIConsentPresenter.handleSheetDismissed()
        }) {
            ThirdPartyAIConsentSheet(
                onContinue: { thirdPartyAIConsentPresenter.confirmContinue() },
                onNotNow: { thirdPartyAIConsentPresenter.decline() }
            )
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
            if authenticationLifecycle.initialRestoreCompleted
                || authenticationManager.state.authFlowPhase == .unauthenticated
            {
                isLaunchBootstrapping = false
            }
            Task {
                await authenticationLifecycle.applicationDidLaunch()
            }
        }
        .onChange(of: authenticationManager.state) { _, newState in
            authenticationCoordinator.syncNavigation(with: newState)
            if case .sessionValidationFailed = newState {
                isLaunchBootstrapping = false
            }
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
                profileOnboardingGate.noteAppBecameActive()
                Task {
                    await authenticationLifecycle.applicationWillEnterForeground()
                    if !launchController.isDemoExperienceActive {
                        appEnvironment.data.realtimeHub.resumeIfNeeded()
                        await AnalyticsRevisionRepairCoordinator.shared.requestRepair(.foreground)
                        GettingStartedStore.shared.onForeground()
                    }
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
        .onChange(of: navigation.store.selectedTab) { _, _ in
            OwnerAccountFilterDropdownController.shared.dismiss()
        }
        .environment(themeManager)
    }

    @ViewBuilder
    private var authRootContent: some View {
        if launchController.isDemoExperienceActive {
            demoExperienceShell
        } else if shouldPresentSignInRoot {
            signInRoot
        } else {
            switch authenticationManager.state {
            case .unknown, .refreshing:
                if authenticationManager.isValidationRetryInFlight {
                    sessionValidationSurface(isRetrying: true)
                } else {
                    SplashView()
                        .onAppear { StartupTrace.event("launchLoadingPresented") }
                }

            case .sessionValidationFailed:
                sessionValidationSurface(isRetrying: false)

            case .authenticated, .locked:
                if navigation.store.sessionPhase == .authenticated, authenticationManager.state.isSessionReady {
                    authenticatedShell
                } else {
                    SplashView()
                }

            case .unauthenticated, .failure, .authenticating:
                signInRoot
            }
        }
    }

    /// Sign-in root takes precedence over session-validation recovery once auth is definitively cleared.
    private var shouldPresentSignInRoot: Bool {
        switch authenticationManager.state {
        case .unauthenticated, .failure:
            return true
        case .sessionValidationFailed(_, let error):
            return error.isTerminalRefreshFailure
        default:
            return false
        }
    }

    private var signInRoot: some View {
        AuthInfrastructureView(
            store: navigation.store,
            coordinator: navigation.coordinator,
            authenticationCoordinator: authenticationCoordinator,
            authenticationManager: authenticationManager,
            allowsDevelopmentBypass: allowsDevelopmentBypass
        )
        .onAppear {
            UnauthLaunchProbe.loginFirstFramePresented()
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
                    ),
                    imagePipeline: appEnvironment.data.imagePipeline,
                    onSignOut: {
                        Task { await authenticationCoordinator.logout() }
                    }
                )

            case .brokerOnboarding:
                BrokerOnboardingView(
                    data: appEnvironment.data,
                    gateStore: profileOnboardingGate
                )

            case .complete:
                mainAuthenticatedShell

            case .connectivityBlocked(let message):
                ProfileOnboardingResolveView(
                    message: message,
                    isRetrying: false,
                    presentation: .connectivity,
                    onRetry: {
                        profileOnboardingGate.resolveIfNeeded(forceNetwork: true)
                    },
                    onSignOut: {
                        Task { await authenticationCoordinator.logout() }
                    }
                )

            case .failed(let message):
                ProfileOnboardingResolveView(
                    message: message,
                    isRetrying: false,
                    presentation: .generic,
                    onRetry: {
                        profileOnboardingGate.resolveIfNeeded(forceNetwork: true)
                    },
                    onSignOut: {
                        Task { await authenticationCoordinator.logout() }
                    }
                )
            }
        }
    }

    private var demoExperienceShell: some View {
        MainTabShellView(
            store: navigation.store,
            coordinator: navigation.coordinator,
            authenticationCoordinator: authenticationCoordinator,
            currentUserProfile: currentUserProfile,
            showsDemoExperienceChrome: true
        )
        .ownerAccountFilterDropdownOverlay()
        .demoExperienceShellChrome()
    }

    private var mainAuthenticatedShell: some View {
        MainTabShellView(
            store: navigation.store,
            coordinator: navigation.coordinator,
            authenticationCoordinator: authenticationCoordinator,
            currentUserProfile: currentUserProfile
        )
        .ownerAccountFilterDropdownOverlay()
        .onChange(of: navigation.store.selectedTab) { _, _ in
            OwnerAccountFilterDropdownController.shared.dismiss()
        }
        .task(id: authenticationManager.restorationGeneration) {
            await MainThreadOperationTracker.trackAsync("shell.authenticatedBootstrap") {
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
            onSignOut: {
                Task { await authenticationCoordinator.logout() }
            }
        )
    }

    private var sessionValidationMessage: String {
        guard let error = authenticationManager.lastSessionValidationError else {
            return "Check your connection and try again, or sign out to continue."
        }
        if error.isTransientRefreshFailure {
            switch error {
            case .unknown(let reason) where reason == "networkUnavailable":
                return "You're offline. Connect to the internet and try again."
            case .unknown(let reason) where reason == "refreshTimeout":
                return "Restoring your session is taking too long. Try again or sign out to continue."
            case .unknown(let reason) where reason == "serverUnavailable":
                return "Our servers are temporarily unavailable. Try again shortly."
            default:
                return "We couldn't reach the server. Try again or sign out to continue."
            }
        }
        return "Your session could not be restored. Sign out to return to the sign-in screen."
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
                        onRecordWithdrawal: {
                            ExperienceHaptics.play(.selection)
                            navigation.coordinator.dismissSheet()
                            navigation.coordinator.openCompose(.withdrawal)
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
                case .tradeImportReminder:
                    TradeImportReminderDestinationView(
                        data: appEnvironment.data,
                        navigation: navigation.coordinator,
                        onClose: { navigation.coordinator.dismissSheet() }
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
            .experienceSheetChrome(
                detents: detents(for: destination),
                interactiveDismiss: !requiresProtectedFormDismiss(destination)
            )
        }
        .experienceProtectedFormDismiss(requiresProtectedFormDismiss(destination))
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
                        initialTab: TradeEntryLaunchIntent.consumeHubTab() ?? .manual,
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
                        prefill: CreateAchievementPrefillStore.shared.consume(),
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
                case .withdrawal:
                    WithdrawalFlowView(
                        data: appEnvironment.data,
                        navigationCoordinator: navigation.coordinator,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .importCSV:
                    TradeEntryHubView(
                        data: appEnvironment.data,
                        initialTab: .csv,
                        onDismiss: { navigation.coordinator.dismissFullScreen() }
                    )
                case .upgrade:
                    TraxProMembershipInfoView(
                        onClose: { navigation.coordinator.dismissFullScreen() },
                        onViewSubscription: IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled
                            ? {
                                navigation.coordinator.dismissFullScreen()
                                navigation.coordinator.open(.settingsStack([.home, .subscription]))
                            }
                            : nil
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
        .experienceProtectedFormDismiss(fullScreenRequiresProtectedFormDismiss(destination))
        .experienceKeyboardDismissOnTapOutside()
        .experienceKeyboardDoneToolbar()
    }

    private func requiresProtectedFormDismiss(_ destination: SheetDestination) -> Bool {
        switch destination {
        case .dailyCheckIn:
            return true
        default:
            return false
        }
    }

    private func fullScreenRequiresProtectedFormDismiss(_ destination: FullScreenDestination) -> Bool {
        switch destination {
        case .addTrade, .editTrade, .importCSV, .importReview, .newPost, .newAchievement, .newReel, .newStory:
            return true
        default:
            return false
        }
    }

    private func detents(for destination: SheetDestination) -> Set<PresentationDetent> {
        switch destination {
        case .composeChooser:
            return [.fraction(0.60)]
        case .dailyCheckIn:
            return [.fraction(0.65)]
        case .tradeImportReminder:
            return [.fraction(0.55)]
        case .quickTrade, .accountSwitcher:
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
        case .tradeImportReminder: return "Import Trades"
        }
    }

    private func fullScreenTitle(_ destination: FullScreenDestination) -> String {
        switch destination {
        case .addTrade: return "Add Trade"
        case .editTrade: return "Edit Trade"
        case .importCSV: return "Add Trade"
        case .importReview: return "Review Import"
        case .newPost: return "New Post"
        case .newAchievement: return "New Achievement"
        case .newReel: return "New Clip"
        case .newStory: return "New Story"
        case .withdrawal: return "Withdrawal"
        case .upgrade: return "TraxPro"
        case .mediaViewer: return "Media"
        case .storyViewer: return "Story"
        }
    }
}
