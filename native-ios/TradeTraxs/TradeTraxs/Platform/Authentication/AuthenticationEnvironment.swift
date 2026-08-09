import Foundation
import OSLog

/// Authentication subgraph injected through ``DependencyContainer`` / ``AppEnvironment``.
final class AuthenticationEnvironment {
    let configuration: AuthenticationConfiguration
    let manager: AuthenticationManager
    let coordinator: AuthenticationCoordinator
    let lifecycle: AuthenticationLifecycle
    let sessionManager: SessionManager
    let sessionBridge: AuthenticationSessionBridge
    let emailProvider: any AuthenticationProviding
    let appleProvider: any OAuthProviding
    let googleProvider: any OAuthProviding
    let passkeys: any PasskeyAuthenticating

    init(
        configuration: AuthenticationConfiguration,
        manager: AuthenticationManager,
        coordinator: AuthenticationCoordinator,
        lifecycle: AuthenticationLifecycle,
        sessionManager: SessionManager,
        sessionBridge: AuthenticationSessionBridge,
        emailProvider: any AuthenticationProviding,
        appleProvider: any OAuthProviding,
        googleProvider: any OAuthProviding,
        passkeys: any PasskeyAuthenticating
    ) {
        self.configuration = configuration
        self.manager = manager
        self.coordinator = coordinator
        self.lifecycle = lifecycle
        self.sessionManager = sessionManager
        self.sessionBridge = sessionBridge
        self.emailProvider = emailProvider
        self.appleProvider = appleProvider
        self.googleProvider = googleProvider
        self.passkeys = passkeys
    }

    static func make(
        appConfiguration: AppConfiguration,
        navigation: NavigationEnvironment,
        keychain: (any KeychainServicing)? = nil,
        backend: (any AuthenticationBackend)? = nil
    ) -> AuthenticationEnvironment {
        let authConfiguration = AuthenticationConfiguration.make(
            for: appConfiguration.buildConfiguration
        )
        let keychainService = keychain ?? KeychainService()
        let credentials = SecureCredentialStore(
            keychain: keychainService,
            configuration: authConfiguration
        )
        let tokens = TokenStore(keychain: keychainService, configuration: authConfiguration)
        let sessionStore = SessionStore(credentials: credentials, tokens: tokens)
        let expiration = SessionExpiration(leeway: authConfiguration.refreshLeeway)
        let sessionManager = SessionManager(store: sessionStore, expiration: expiration)
        let sessionBridge = AuthenticationSessionBridge(sessionManager: sessionManager)

        let authBackend = backend ?? PlaceholderAuthenticationBackend()
        let emailProvider = EmailAuthenticationProvider(backend: authBackend)
        let appleProvider = AppleSignInProvider(backend: authBackend)
        let googlePerformer: any GoogleSignInPerforming = appConfiguration.isSupabaseConfigured
            ? SupabaseGoogleOAuthPerformer(configuration: appConfiguration)
            : GoogleIDTokenSignInPerformer(
                backend: authBackend,
                credentialSource: UnavailableGoogleCredentialSource()
            )
        let googleProvider = GoogleSignInProvider(performer: googlePerformer)
        let passkeys = FuturePasskeySupport()

        let refreshCoordinator = TokenRefreshCoordinator(
            sessionManager: sessionManager,
            emailProvider: emailProvider,
            expiration: expiration
        )
        let logoutCoordinator = LogoutCoordinator(
            sessionManager: sessionManager,
            emailProvider: emailProvider,
            credentials: credentials
        )
        let biometrics: any BiometricAuthenticating = authConfiguration.biometricUnlockEnabled
            ? BiometricAuthenticationSupport()
            : DisabledBiometricAuthenticationSupport()
        let migration = CredentialMigration(configuration: authConfiguration)

        let manager = AuthenticationManager(
            configuration: authConfiguration,
            sessionManager: sessionManager,
            emailProvider: emailProvider,
            appleProvider: appleProvider,
            googleProvider: googleProvider,
            refreshCoordinator: refreshCoordinator,
            logoutCoordinator: logoutCoordinator,
            biometrics: biometrics,
            migration: migration
        )
        let coordinator = AuthenticationCoordinator(
            authenticationManager: manager,
            navigation: navigation
        )
        let lifecycle = AuthenticationLifecycle(
            authenticationManager: manager,
            authenticationCoordinator: coordinator
        )

        AppLog.authentication.info("AuthenticationEnvironment ready")

        return AuthenticationEnvironment(
            configuration: authConfiguration,
            manager: manager,
            coordinator: coordinator,
            lifecycle: lifecycle,
            sessionManager: sessionManager,
            sessionBridge: sessionBridge,
            emailProvider: emailProvider,
            appleProvider: appleProvider,
            googleProvider: googleProvider,
            passkeys: passkeys
        )
    }
}
