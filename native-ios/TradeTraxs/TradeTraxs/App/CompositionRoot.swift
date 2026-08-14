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
                tokenSource.token()
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
        InboxMarkReadCoordinator.shared.configure(
            messages: data.messages,
            rooms: data.rooms,
            session: data.session
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
        AppLog.authentication.debug(
            "Auth state after cold launch: \(String(describing: authState), privacy: .public)"
        )

        let currentUserProfile = CurrentUserProfileStore(
            profiles: data.profiles,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache
        )

        let pushNotifications = PushNotificationCenter(
            tokenClient: DevicePushTokenClient(transport: transport),
            navigation: navigation
        )
        pushNotifications.attachNotificationsRepository(data.notifications)

        // Session caches belong to the authenticated user — invalidate on logout / switch.
        authentication.coordinator.invalidateSessionCaches = {
            pushNotifications.unregisterForLogout()
            SessionScopedCaches.invalidate(
                currentUserProfile: currentUserProfile,
                data: data
            )
        }
        authentication.coordinator.onAuthenticatedSessionBound = {
            pushNotifications.syncRegistrationForAuthenticatedSession()
        }

        // Cold restore already authenticated — register once the graph exists.
        if authentication.manager.state.isAuthenticated {
            pushNotifications.syncRegistrationForAuthenticatedSession()
        }

        return AppEnvironment(
            configuration: configuration,
            featureFlags: featureFlags,
            dependencies: dependencies,
            lifecycle: lifecycle,
            themeManager: themeManager,
            currentUserProfile: currentUserProfile,
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
        let state = NavigationRestorationPolicy.bootstrapState(restorer: restorer)
        let store = NavigationStore(state: state)
        let coordinator = NavigationCoordinator(store: store)
        return NavigationEnvironment(
            store: store,
            coordinator: coordinator,
            stateRestorer: restorer
        )
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
