import Foundation
import OSLog

/// Sole place that constructs production (or fake) application services.
///
/// Tests may call ``bootstrap()`` or ``bootstrapAuthenticationForTests`` with fakes.
/// No service-locator / runtime container lookup.
enum CompositionRoot {
    /// Builds the launch-time ``AppEnvironment``.
    static func bootstrap() -> AppEnvironment {
        AppLog.application.info("CompositionRoot.bootstrap — Phase 4B Supabase integration")

        let configuration = AppConfiguration.make(for: .current)
        let featureFlags = FeatureFlags.make(for: configuration.buildConfiguration)
        let lifecycle = AppLifecycleHandler()
        let themeManager = ThemeManager()

        let navigation = makeNavigationEnvironment()

        // Networking is created before auth so GoTrue / PostgREST share one client.
        // Token source is bound after SessionManager exists.
        let tokenSource = AccessTokenSource()
        let networking = NetworkingEnvironment.make(
            appConfiguration: configuration,
            accessTokenProvider: {
                await SessionNetworkGate.shared.awaitReady()
                return tokenSource.token()
            }
        )

        let transport = SupabaseTransport(
            client: networking.client,
            requestBuilder: networking.requestBuilder,
            configuration: configuration
        )
        let authBackend = SupabaseAuthenticationBackend(transport: transport)

        let authentication = AuthenticationEnvironment.make(
            appConfiguration: configuration,
            navigation: navigation,
            backend: authBackend
        )
        tokenSource.bind { authentication.sessionManager.accessToken }

        // Keychain wins over any restored Navigation sessionPhase.
        let authState = authentication.manager.prepareColdLaunch()
        authentication.coordinator.syncNavigation(with: authState)

        let data = DataEnvironment.make(
            appConfiguration: configuration,
            networking: networking,
            session: authentication.sessionBridge,
            authenticationManager: authentication.manager
        )
        authentication.manager.sessionBootstrap = AuthenticatedSessionBootstrap(
            profiles: data.profiles,
            backend: authBackend
        )
        InboxMarkReadCoordinator.shared.configure(
            messages: data.messages,
            rooms: data.rooms,
            session: data.session
        )
        AppIconBadgeSync.configure(
            client: AppIconBadgeClient(transport: transport)
        )
        let dependencies = DependencyContainer.make(
            configuration: configuration,
            navigation: navigation,
            networking: networking,
            data: data,
            authentication: authentication
        )

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
            session: authentication.sessionManager.currentSession,
            expiration: SessionExpiration(leeway: authentication.configuration.refreshLeeway)
        )
        BackendV2FeatureFlags.logStartupFlags()

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

        let pushNotifications = MainActor.assumeIsolated {
            PushNotificationCenter(
                tokenClient: DevicePushTokenClient(transport: transport),
                navigation: navigation,
                activityInbox: .shared,
                badgeController: .shared,
                routerFacade: NotificationRouterFacade(router: NotificationRouter())
            )
        }
        pushNotifications.attachNotificationsRepository(data.notifications)

        // Session caches belong to the authenticated user — invalidate on logout / switch.
        authentication.coordinator.prepareSessionTeardown = {
            await pushNotifications.unregisterForLogout()
        }
        authentication.coordinator.invalidateSessionCaches = {
            SessionScopedCaches.invalidate(
                currentUserProfile: currentUserProfile,
                data: data
            )
            appBootstrapState.reset()
            profileOnboardingGate.reset()
        }
        authentication.coordinator.onAuthenticatedSessionBound = {
            Task {
                await authentication.manager.awaitNetworkReady()
                pushNotifications.syncRegistrationForAuthenticatedSession()
            }
        }

        // Push registration runs after session restore via onAuthenticatedSessionBound.

        return AppEnvironment(
            configuration: configuration,
            featureFlags: featureFlags,
            dependencies: dependencies,
            lifecycle: lifecycle,
            themeManager: themeManager,
            currentUserProfile: currentUserProfile,
            appBootstrapState: appBootstrapState,
            profileOnboardingGate: profileOnboardingGate,
            pushNotifications: pushNotifications
        )
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
