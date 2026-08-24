import Foundation
import Observation
import OSLog

/// Owns authentication state. Features observe ``state`` — they never touch Keychain.
@Observable
final class AuthenticationManager {
    private(set) var state: AuthenticationState = .unknown
    private(set) var lastEvent: AuthenticationEvent?

    private let configuration: AuthenticationConfiguration
    private let sessionManager: SessionManager
    private let emailProvider: any AuthenticationProviding
    private let appleProvider: any OAuthProviding
    private let googleProvider: any OAuthProviding
    private let refreshCoordinator: TokenRefreshCoordinator
    private let logoutCoordinator: LogoutCoordinator
    private let biometrics: any BiometricAuthenticating
    private let migration: any CredentialMigrating
    private let validator: AuthenticationValidator

    init(
        configuration: AuthenticationConfiguration,
        sessionManager: SessionManager,
        emailProvider: any AuthenticationProviding,
        appleProvider: any OAuthProviding,
        googleProvider: any OAuthProviding,
        refreshCoordinator: TokenRefreshCoordinator,
        logoutCoordinator: LogoutCoordinator,
        biometrics: any BiometricAuthenticating,
        migration: any CredentialMigrating,
        validator: AuthenticationValidator = AuthenticationValidator()
    ) {
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.emailProvider = emailProvider
        self.appleProvider = appleProvider
        self.googleProvider = googleProvider
        self.refreshCoordinator = refreshCoordinator
        self.logoutCoordinator = logoutCoordinator
        self.biometrics = biometrics
        self.migration = migration
        self.validator = validator

        refreshCoordinator.setHandlers(
            onRefreshed: { [weak self] session in
                self?.applyAuthenticated(session, event: .tokenRefreshSucceeded)
            },
            onFailed: { [weak self] error in
                self?.emit(.tokenRefreshFailed)
                if case .refreshFailed = error {
                    Task { await self?.handleExpiredSession() }
                }
            }
        )
    }

    var sessionManagerForNetworking: SessionManager { sessionManager }

    // MARK: - Lifecycle

    /// Synchronous Keychain restore for CompositionRoot cold launch (no network).
    @discardableResult
    func prepareColdLaunch() -> AuthenticationState {
        emit(.restorationStarted)
        do {
            try migration.migrateIfNeeded()
            guard let session = try sessionManager.restoreFromStore() else {
                state = .unauthenticated
                emit(.restorationFailed)
                return state
            }
            if session.isExpired, session.refreshToken != nil {
                state = .refreshing(session)
                return state
            }
            if session.isExpired {
                try sessionManager.destroy()
                state = .unauthenticated
                emit(.sessionExpired)
                return state
            }
            applyAuthenticated(session, event: .restorationSucceeded(userID: session.userID))
            refreshCoordinator.schedule(for: session)
            return state
        } catch {
            state = .unauthenticated
            emit(.restorationFailed)
            AppLog.authentication.error("Session restore failed")
            return state
        }
    }

    /// Completes restore when a refresh token hop is required.
    func restoreSession() async {
        if state == .unknown {
            _ = prepareColdLaunch()
        }
        if case .refreshing = state {
            emit(.tokenRefreshStarted)
            AuthFlowTracer.trace("session.validation.started", phase: .restoring)
            await refreshCoordinator.refreshNow()
            if case .authenticated(let session) = state {
                emit(.restorationSucceeded(userID: session.userID))
                AuthFlowTracer.trace("session.validation.completed", phase: .authenticated)
            } else if !state.isAuthenticated {
                state = .unauthenticated
                emit(.restorationFailed)
                AuthFlowTracer.trace("session.validation.completed", phase: .unauthenticated)
            }
        }
    }

    // MARK: - Sign in / up

    func signIn(email: String, password: String) async throws {
        try await authenticate(provider: .email) {
            try await emailProvider.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String) async throws {
        try await authenticate(provider: .email) {
            try await emailProvider.signUp(email: email, password: password)
        }
    }

    func signInWithApple() async throws {
        try await authenticate(provider: .apple) {
            try await appleProvider.signIn()
        }
    }

    func signInWithGoogle() async throws {
        try await authenticate(provider: .google) {
            try await googleProvider.signIn()
        }
    }

    /// Debug-only path that still uses Keychain + state machine (not a navigation hack).
    func issueDevelopmentSession() async throws {
        guard configuration.allowsDevelopmentSessionBypass else {
            throw AuthenticationError.notConfigured
        }
        let session = AuthenticationSession(
            userID: UserID("dev.\(UUID().uuidString)"),
            email: "developer@tradetraxs.local",
            accessToken: "dev.access.\(UUID().uuidString)",
            refreshToken: "dev.refresh.\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(60 * 60 * 24),
            provider: .development,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
        try await complete(session: session)
    }

    func requestPasswordReset(email: String) async throws {
        if let error = validator.validateEmail(email) { throw error }
        try await emailProvider.requestPasswordReset(email: email)
    }

    // MARK: - Logout / lock

    func logout() async {
        emit(.logoutStarted)
        refreshCoordinator.cancel()
        await logoutCoordinator.logout()
        state = .unauthenticated
        emit(.logoutCompleted)
    }

    func unlockWithBiometrics(reason: String = "Unlock TradeTraxs") async throws {
        guard case .locked(let session) = state else { return }
        guard configuration.biometricUnlockEnabled else {
            throw AuthenticationError.biometricUnavailable
        }
        do {
            try await biometrics.evaluate(reason: reason)
            applyAuthenticated(session, event: .biometricUnlockSucceeded)
            refreshCoordinator.schedule(for: session)
        } catch {
            emit(.biometricUnlockFailed)
            throw AuthenticationError.biometricFailed
        }
    }

    func switchProvider(to kind: AuthenticationProviderKind) {
        // Provider selection is UI state; managers keep registered providers ready.
        _ = kind
        emit(.signInStarted(kind))
        state = .authenticating(kind)
    }

    // MARK: - Private

    private func authenticate(
        provider: AuthenticationProviderKind,
        operation: () async throws -> AuthenticationSession
    ) async throws {
        state = .authenticating(provider)
        emit(.signInStarted(provider))
        defer {
            if case .authenticating = state {
                state = .unauthenticated
            }
        }
        do {
            let session = try await operation()
            try await complete(session: session)
        } catch is CancellationError {
            if case .authenticating = state {
                state = .unauthenticated
            }
            emit(.signInFailed(.cancelled))
            throw CancellationError()
        } catch let error as AuthenticationError {
            state = .failure(error)
            emit(.signInFailed(error))
            throw error
        } catch {
            let mapped = AuthenticationError.unknown(error.localizedDescription)
            state = .failure(mapped)
            emit(.signInFailed(mapped))
            throw mapped
        }
    }

    private func complete(session: AuthenticationSession) async throws {
        try sessionManager.install(session)
        applyAuthenticated(
            session,
            event: .signInSucceeded(userID: session.userID, provider: session.provider)
        )
        refreshCoordinator.schedule(for: session)
    }

    private func applyAuthenticated(_ session: AuthenticationSession, event: AuthenticationEvent) {
        state = .authenticated(session)
        emit(event)
    }

    private func handleExpiredSession() async {
        emit(.sessionExpired)
        await logout()
    }

    private func emit(_ event: AuthenticationEvent) {
        lastEvent = event
        AppLog.authentication.info("Auth event: \(String(describing: event), privacy: .public)")
    }
}
