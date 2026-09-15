import Foundation
import OSLog

struct CompositionBootstrapResult {
    let environment: AppEnvironment
    let deferredContext: DeferredBootstrapContext?
}

/// Carries launch-critical state until the logged-out shell upgrades to the full stack.
struct DeferredBootstrapContext {
    let configuration: AppConfiguration
    let featureFlags: FeatureFlags
    let lifecycle: AppLifecycleHandler
    let themeManager: ThemeManager
    let navigation: NavigationEnvironment
    let authentication: AuthenticationEnvironment
    let tokenSource: AccessTokenSource
    let swappableBackend: SwappableAuthenticationBackend
    let swappableGooglePerformer: SwappableGoogleSignInPerformer
}

/// Sole place that constructs production (or fake) application services.
///
/// Tests may call ``bootstrap()`` or ``bootstrapAuthenticationForTests`` with fakes.
/// No service-locator / runtime container lookup.
enum CompositionRoot {
    /// Builds the launch-time ``AppEnvironment``.
    static func bootstrap() -> CompositionBootstrapResult {
        StartupTrace.begin("CompositionRoot.bootstrap")
        defer { StartupTrace.end("CompositionRoot.bootstrap") }
        AppLog.application.info("CompositionRoot.bootstrap — Phase 4B Supabase integration")
        UnauthLaunchProbe.recordAppStart()

        let configuration = StartupTrace.measure("AppConfiguration.make") {
            AppConfiguration.make(for: .current)
        }
        StartupTrace.measure("AppConfigurationValidator") {
            AppConfigurationValidator.assertReadyForLaunch(configuration)
        }
        let featureFlags = StartupTrace.measure("FeatureFlags.make") {
            FeatureFlags.make(for: configuration.buildConfiguration)
        }
        let lifecycle = AppLifecycleHandler()
        let themeManager = ThemeManager()

        let navigation = StartupTrace.measure("makeNavigationEnvironment") {
            makeNavigationEnvironment()
        }

        let tokenSource = AccessTokenSource()
        let authLaunch = StartupTrace.measure("AuthenticationEnvironment.makeForLaunch") {
            AuthenticationEnvironment.makeForLaunch(
                appConfiguration: configuration,
                navigation: navigation
            )
        }
        let authentication = authLaunch.environment

        let authState = StartupTrace.measure("prepareColdLaunch") {
            authentication.manager.prepareColdLaunch()
        }
        authentication.coordinator.syncNavigation(with: authState)
        authentication.lifecycle.markInitialRestoreCompletedIfLoggedOut()
        StartupTrace.event("authStateResolved")

        switch authState {
        case .unauthenticated, .failure:
            let shell = buildLoggedOutLoginShell(
                configuration: configuration,
                featureFlags: featureFlags,
                lifecycle: lifecycle,
                themeManager: themeManager,
                navigation: navigation,
                authentication: authentication,
                tokenSource: tokenSource
            )
            let deferred = DeferredBootstrapContext(
                configuration: configuration,
                featureFlags: featureFlags,
                lifecycle: lifecycle,
                themeManager: themeManager,
                navigation: navigation,
                authentication: authentication,
                tokenSource: tokenSource,
                swappableBackend: authLaunch.swappableBackend,
                swappableGooglePerformer: authLaunch.swappableGooglePerformer
            )
            return CompositionBootstrapResult(environment: shell, deferredContext: deferred)

        case .unknown, .refreshing, .authenticated, .locked, .sessionValidationFailed, .authenticating:
            let environment = buildProductionEnvironment(
                configuration: configuration,
                featureFlags: featureFlags,
                lifecycle: lifecycle,
                themeManager: themeManager,
                navigation: navigation,
                authentication: authentication,
                tokenSource: tokenSource,
                swappableBackend: authLaunch.swappableBackend,
                swappableGooglePerformer: authLaunch.swappableGooglePerformer,
                authState: authState
            )
            return CompositionBootstrapResult(environment: environment, deferredContext: nil)
        }
    }

    /// Production stack for logged-out shell — heavy construction off MainActor; wiring on MainActor.
    @MainActor
    static func completeDeferredBootstrap(context: DeferredBootstrapContext) async -> AppEnvironment {
        let configuration = context.configuration
        let authentication = context.authentication
        let tokenSource = context.tokenSource

        let networking = await Task.detached(priority: .userInitiated) { @Sendable in
            await MainActor.run {
                StartupTrace.measure("NetworkingEnvironment.make.detached") {
                    NetworkingEnvironment.make(
                        appConfiguration: configuration,
                        accessTokenProvider: {
                            await SessionNetworkGate.shared.awaitReady()
                            return tokenSource.token()
                        }
                    )
                }
            }
        }.value

        tokenSource.bind { authentication.sessionManager.accessToken }

        let transport = SupabaseTransport(
            client: networking.client,
            requestBuilder: networking.requestBuilder,
            configuration: configuration
        )
        let authBackend = SupabaseAuthenticationBackend(transport: transport)
        context.swappableBackend.install(authBackend)
        if configuration.isSupabaseConfigured {
            context.swappableGooglePerformer.install(
                SupabaseGoogleOAuthPerformer(
                    configuration: configuration,
                    backend: authBackend
                )
            )
        }

        let data = await Task.detached(priority: .userInitiated) { @Sendable in
            await MainActor.run {
                StartupTrace.measure("DataEnvironment.make.detached") {
                    DataEnvironment.make(
                        appConfiguration: configuration,
                        networking: networking,
                        session: authentication.sessionBridge,
                        authenticationManager: authentication.manager,
                        launchMode: .production
                    )
                }
            }
        }.value

        return StartupTrace.measure("CompositionRoot.assembleProductionEnvironment") {
            assembleProductionEnvironment(
                configuration: configuration,
                featureFlags: context.featureFlags,
                lifecycle: context.lifecycle,
                themeManager: context.themeManager,
                navigation: context.navigation,
                authentication: authentication,
                tokenSource: tokenSource,
                networking: networking,
                data: data,
                transport: transport,
                authBackend: authBackend,
                authState: authentication.manager.state
            )
        }
    }

    // MARK: - Logged-out shell

    private static func buildLoggedOutLoginShell(
        configuration: AppConfiguration,
        featureFlags: FeatureFlags,
        lifecycle: AppLifecycleHandler,
        themeManager: ThemeManager,
        navigation: NavigationEnvironment,
        authentication: AuthenticationEnvironment,
        tokenSource: AccessTokenSource
    ) -> AppEnvironment {
        let data = StartupTrace.measure("DataEnvironment.makeLoginShell") {
            DataEnvironment.make(
                appConfiguration: configuration,
                session: authentication.sessionBridge,
                authenticationManager: authentication.manager,
                launchMode: .loginShell
            )
        }
        let dependencies = DependencyContainer.make(
            configuration: configuration,
            navigation: navigation,
            networking: nil,
            data: data,
            authentication: authentication
        )
        let currentUserProfile = CurrentUserProfileStore(
            profiles: data.profiles,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache,
            rpc: data.rpc
        )
        let appBootstrapState = AppBootstrapState()
        let profileOnboardingGate = ProfileOnboardingGateStore(
            profiles: data.profiles,
            session: data.session,
            rpc: data.rpc,
            detailCache: data.detailCache,
            realtimeHub: data.realtimeHub,
            profileStore: currentUserProfile
        )
        let contentReportPresenter = MainActor.assumeIsolated {
            ContentReportPresenter()
        }
        let pushNotifications = MainActor.assumeIsolated {
            PushNotificationCenter(
                tokenClient: LoginShellDevicePushTokenClient(),
                navigation: navigation,
                activityInbox: .shared,
                badgeController: .shared,
                routerFacade: NotificationRouterFacade(router: NotificationRouter())
            )
        }
        logLaunchSummary(
            configuration: configuration,
            themeManager: themeManager,
            authState: authentication.manager.state,
            session: authentication.sessionManager.currentSession
        )
        return AppEnvironment(
            configuration: configuration,
            featureFlags: featureFlags,
            dependencies: dependencies,
            lifecycle: lifecycle,
            themeManager: themeManager,
            currentUserProfile: currentUserProfile,
            appBootstrapState: appBootstrapState,
            profileOnboardingGate: profileOnboardingGate,
            pushNotifications: pushNotifications,
            contentReportPresenter: contentReportPresenter
        )
    }

    // MARK: - Full production stack

    private static func buildProductionEnvironment(
        configuration: AppConfiguration,
        featureFlags: FeatureFlags,
        lifecycle: AppLifecycleHandler,
        themeManager: ThemeManager,
        navigation: NavigationEnvironment,
        authentication: AuthenticationEnvironment,
        tokenSource: AccessTokenSource,
        swappableBackend: SwappableAuthenticationBackend,
        swappableGooglePerformer: SwappableGoogleSignInPerformer,
        authState: AuthenticationState
    ) -> AppEnvironment {
        let networking = StartupTrace.measure("NetworkingEnvironment.make") {
            NetworkingEnvironment.make(
                appConfiguration: configuration,
                accessTokenProvider: {
                    await SessionNetworkGate.shared.awaitReady()
                    return tokenSource.token()
                }
            )
        }
        tokenSource.bind { authentication.sessionManager.accessToken }

        let transport = SupabaseTransport(
            client: networking.client,
            requestBuilder: networking.requestBuilder,
            configuration: configuration
        )
        let authBackend = SupabaseAuthenticationBackend(transport: transport)
        swappableBackend.install(authBackend)
        if configuration.isSupabaseConfigured {
            swappableGooglePerformer.install(
                SupabaseGoogleOAuthPerformer(
                    configuration: configuration,
                    backend: authBackend
                )
            )
        }

        let data = StartupTrace.measure("DataEnvironment.make") {
            DataEnvironment.make(
                appConfiguration: configuration,
                networking: networking,
                session: authentication.sessionBridge,
                authenticationManager: authentication.manager,
                launchMode: .production
            )
        }

        return assembleProductionEnvironment(
            configuration: configuration,
            featureFlags: featureFlags,
            lifecycle: lifecycle,
            themeManager: themeManager,
            navigation: navigation,
            authentication: authentication,
            tokenSource: tokenSource,
            networking: networking,
            data: data,
            transport: transport,
            authBackend: authBackend,
            authState: authState
        )
    }

    @MainActor
    private static func assembleProductionEnvironment(
        configuration: AppConfiguration,
        featureFlags: FeatureFlags,
        lifecycle: AppLifecycleHandler,
        themeManager: ThemeManager,
        navigation: NavigationEnvironment,
        authentication: AuthenticationEnvironment,
        tokenSource: AccessTokenSource,
        networking: NetworkingEnvironment,
        data: DataEnvironment,
        transport: SupabaseTransport,
        authBackend: SupabaseAuthenticationBackend,
        authState: AuthenticationState
    ) -> AppEnvironment {
        authentication.manager.sessionBootstrap = AuthenticatedSessionBootstrap(
            profiles: data.profiles,
            backend: authBackend
        )
        InboxMarkReadCoordinator.shared.configure(
            messages: data.messages,
            rooms: data.rooms,
            session: data.session
        )
        let sessionManager = authentication.sessionManager
        AppIconBadgeSync.configure(
            client: AppIconBadgeClient(transport: transport),
            canFetchAuthenticatedBadge: {
                await SessionNetworkGate.shared.awaitReady()
                guard let token = sessionManager.accessToken, !token.isEmpty else { return false }
                return true
            }
        )
        let dependencies = DependencyContainer.make(
            configuration: configuration,
            navigation: navigation,
            networking: networking,
            data: data,
            authentication: authentication
        )

        logLaunchSummary(
            configuration: configuration,
            themeManager: themeManager,
            authState: authState,
            session: sessionManager.currentSession
        )

        let currentUserProfile = CurrentUserProfileStore(
            profiles: data.profiles,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache,
            rpc: data.rpc
        )
        let appBootstrapState = AppBootstrapState()
        let profileOnboardingGate = ProfileOnboardingGateStore(
            profiles: data.profiles,
            session: data.session,
            rpc: data.rpc,
            detailCache: data.detailCache,
            realtimeHub: data.realtimeHub,
            profileStore: currentUserProfile
        )
        FollowMutationCoordinator.shared.configure(
            detailCache: data.detailCache,
            currentUserProfile: currentUserProfile
        )
        ViewerSyncStateRuntime.configure(rpc: data.rpc, profiles: data.profiles)

        let pushNotifications = PushNotificationCenter(
            tokenClient: DevicePushTokenClient(transport: transport),
            navigation: navigation,
            activityInbox: .shared,
            badgeController: .shared,
            routerFacade: NotificationRouterFacade(router: NotificationRouter())
        )
        pushNotifications.attachNotificationsRepository(data.notifications)

        authentication.coordinator.prepareSessionTeardown = {
            await pushNotifications.unregisterForLogout()
        }
        authentication.coordinator.prepareAccountDeletion = {
            await pushNotifications.unregisterForAccountDeletion()
            await data.realtimeHub.stop()
        }
        authentication.coordinator.invalidateSessionCaches = {
            SessionScopedCaches.invalidate(
                currentUserProfile: currentUserProfile,
                data: data
            )
            appBootstrapState.reset()
            profileOnboardingGate.reset()
        }
        let authLifecycle = authentication.lifecycle
        Task {
            await NetworkUnauthorizedRecovery.shared.configure { @Sendable in
                await Task { @MainActor in
                    await authentication.coordinator.recoverSessionAfterUnauthorized()
                }.value
            }
        }
        authLifecycle.refreshBillingEntitlementsOnForeground = {
            guard let userID = sessionManager.currentSession?.userID else { return }
            let profileID = ProfileID(userID.rawValue)
            await BillingEntitlementRefreshFlight.shared.refresh {
                do {
                    let refreshed = try await data.billing.refreshEntitlements(for: profileID)
                    await MainActor.run {
                        SessionBillingEntitlementStore.shared.apply(refreshed)
                        NotificationCenter.default.post(
                            name: .billingEntitlementsDidRefresh,
                            object: refreshed
                        )
                    }
                } catch {
                    // Keep last-known entitlement when refresh fails offline.
                }
            }
        }
        authentication.coordinator.onAuthenticatedSessionBound = {
            Task {
                while !authLifecycle.initialRestoreCompleted {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    if Task.isCancelled { return }
                }
                await authentication.manager.awaitNetworkReady()
                guard sessionManager.accessToken?.isEmpty == false else { return }
                pushNotifications.syncRegistrationForAuthenticatedSession()
                pushNotifications.syncBadgeFromActivity()
                await DailyCheckInReminderCoordinator.shared.sync()
                await TradeImportReminderCoordinator.shared.sync()
                BrokerImportEligibilityStore.shared.loadIfNeeded()
                await data.storeKitSubscriptions.startTransactionListenerIfNeeded()
                try? await data.storeKitSubscriptions.syncVerifiedTransactionsToServer()
            }
        }

        let contentReportPresenter = ContentReportPresenter()

        return AppEnvironment(
            configuration: configuration,
            featureFlags: featureFlags,
            dependencies: dependencies,
            lifecycle: lifecycle,
            themeManager: themeManager,
            currentUserProfile: currentUserProfile,
            appBootstrapState: appBootstrapState,
            profileOnboardingGate: profileOnboardingGate,
            pushNotifications: pushNotifications,
            contentReportPresenter: contentReportPresenter
        )
    }

    private static func logLaunchSummary(
        configuration: AppConfiguration,
        themeManager: ThemeManager,
        authState: AuthenticationState,
        session: AuthenticationSession?
    ) {
        AppLog.application.debug(
            "Active build configuration: \(configuration.buildConfiguration.displayName, privacy: .public)"
        )
        AppLog.application.debug(
            "Supabase configured: \(configuration.isSupabaseConfigured, privacy: .public)"
        )
        AppLog.application.debug(
            "Active theme: \(themeManager.selectedIdentifier.rawValue, privacy: .public)"
        )
        SafeAuthLog.logState(
            authState,
            session: session,
            expiration: SessionExpiration(
                leeway: AuthenticationConfiguration.make(for: configuration.buildConfiguration).refreshLeeway
            )
        )
        BackendV2FeatureFlags.logStartupFlags()
    }

    /// Full ``AppEnvironment`` for tests and previews (completes deferred logged-out bootstrap).
    static func bootstrapAppEnvironment() -> AppEnvironment {
        let result = bootstrap()
        guard let deferred = result.deferredContext else { return result.environment }
        return MainActor.assumeIsolated {
            buildProductionEnvironment(
                configuration: deferred.configuration,
                featureFlags: deferred.featureFlags,
                lifecycle: deferred.lifecycle,
                themeManager: deferred.themeManager,
                navigation: deferred.navigation,
                authentication: deferred.authentication,
                tokenSource: deferred.tokenSource,
                swappableBackend: deferred.swappableBackend,
                swappableGooglePerformer: deferred.swappableGooglePerformer,
                authState: deferred.authentication.manager.state
            )
        }
    }

    /// Builds navigation for tests with an explicit starting state.
    static func bootstrapNavigation(
        state: NavigationState = .initial,
        restorer: any NavigationStateRestoring = UserDefaultsNavigationStateRestorer()
    ) -> NavigationEnvironment {
        let store = NavigationStore(state: state)
        let coordinator = NavigationCoordinator(store: store)
        return NavigationEnvironment(
            store: store,
            coordinator: coordinator,
            stateRestorer: restorer
        )
    }

    /// Test helper — authentication graph with in-memory keychain + backend.
    static func bootstrapAuthenticationForTests(
        navigation: NavigationEnvironment? = nil,
        backend: any AuthenticationBackend = InMemoryAuthenticationBackend()
    ) -> AuthenticationEnvironment {
        let configuration = AppConfiguration.make(
            for: .debug,
            secrets: SecretsLoader.Values(
                supabaseURL: nil,
                supabaseAnonKey: nil,
                apiBaseURL: nil
            )
        )
        let nav = navigation ?? bootstrapNavigation()
        return AuthenticationEnvironment.make(
            appConfiguration: configuration,
            navigation: nav,
            keychain: InMemoryKeychainService(),
            backend: backend
        )
    }

    private static func makeNavigationEnvironment() -> NavigationEnvironment {
        let restorer = UserDefaultsNavigationStateRestorer()
        let bootstrap = NavigationRestorationPolicy.bootstrapState(restorer: restorer)
        let store = NavigationStore(state: bootstrap.shellState)
        let coordinator = NavigationCoordinator(store: store)
        let environment = NavigationEnvironment(
            store: store,
            coordinator: coordinator,
            stateRestorer: restorer
        )
        if let deferred = bootstrap.deferredAuthenticatedPaths {
            environment.deferAuthenticatedSnapshot(deferred)
        }
        return environment
    }
}

/// Bridges SessionManager into Networking before the auth graph finishes constructing.
final class AccessTokenSource: @unchecked Sendable {
    private let lock = NSLock()
    private var provider: (() -> String?)?

    func bind(_ provider: @escaping () -> String?) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func token() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return provider?()
    }
}

/// Push token registration deferred until production bootstrap completes.
private struct LoginShellDevicePushTokenClient: DevicePushTokenClienting {
    func register(
        deviceToken: String,
        previousDeviceToken: String?,
        installationID: String?,
        appVersion: String?
    ) async throws {
        _ = (deviceToken, previousDeviceToken, installationID, appVersion)
    }

    func unregister(deviceToken: String?, allDevices: Bool) async throws {
        _ = (deviceToken, allDevices)
    }
}
