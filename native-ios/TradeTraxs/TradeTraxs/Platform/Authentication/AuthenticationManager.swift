import Foundation
import OSLog

/// Owns authentication state. Features observe ``state`` — they never touch Keychain.
@Observable
final class AuthenticationManager {
    private(set) var state: AuthenticationState = .unknown
    private(set) var lastEvent: AuthenticationEvent?
    /// Monotonic attempt id — stale async refresh/restore completions must not publish state.
    private(set) var restorationGeneration: UInt64 = 0

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
    private let expiration: SessionExpiration

    /// Post-auth profile ensure + OAuth first-login metadata (bound after ``DataEnvironment`` exists).
    var sessionBootstrap: AuthenticatedSessionBootstrap?

    private(set) var lastSessionValidationError: AuthenticationError?

    private var restoreInFlight = false
    private var isRetryingValidation = false

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
        validator: AuthenticationValidator = AuthenticationValidator(),
        expiration: SessionExpiration? = nil
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
        self.expiration = expiration ?? SessionExpiration(leeway: configuration.refreshLeeway)

        refreshCoordinator.setHandlers(
            onRefreshed: { [weak self] session in
                self?.applyAuthenticated(session, event: .tokenRefreshSucceeded)
                Task { await SessionNetworkGate.shared.markReady() }
            },
            onFailed: { [weak self] error in
                guard let self else { return }
                Task { await self.handleProactiveRefreshFailure(error) }
            }
        )
        refreshCoordinator.setSessionGenerationProvider { [weak self] in
            self?.restorationGeneration ?? 0
        }
    }

    var sessionManagerForNetworking: SessionManager { sessionManager }

    // MARK: - Lifecycle

    /// Synchronous Keychain restore for CompositionRoot cold launch (no network).
    @discardableResult
    func prepareColdLaunch() -> AuthenticationState {
        emit(.restorationStarted)
        AuthFlowTracer.trace(
            "auth.restore.started",
            phase: .restoring,
            generation: restorationGeneration
        )
        do {
            try migration.migrateIfNeeded()
            guard let session = try sessionManager.restoreFromStore() else {
                state = .unauthenticated
                emit(.restorationFailed)
                traceRestoreSessionFound(expired: false, present: false)
                Task { await SessionNetworkGate.shared.markUnauthenticated() }
                return state
            }
            let expired = expiration.isExpired(session) || expiration.needsRefresh(session)
            traceRestoreSessionFound(expired: expired, present: true)
            if expiration.needsRefresh(session) {
                state = .refreshing(session)
                Task { await SessionNetworkGate.shared.beginRefresh() }
                return state
            }
            if expiration.isExpired(session), session.refreshToken == nil {
                try sessionManager.destroy()
                state = .unauthenticated
                emit(.sessionExpired)
                Task { await SessionNetworkGate.shared.markUnauthenticated() }
                return state
            }
            applyAuthenticated(session, event: .restorationSucceeded(userID: session.userID))
            Task { await SessionNetworkGate.shared.markReady() }
            refreshCoordinator.schedule(for: session)
            return state
        } catch {
            state = .unauthenticated
            emit(.restorationFailed)
            AppLog.authentication.error("Session restore failed")
            Task { await SessionNetworkGate.shared.markUnauthenticated() }
            return state
        }
    }

    /// Authoritative async restore — single-flight refresh when needed.
    func restoreSession() async {
        if restoreInFlight {
            await waitForRestoreCompletion()
            return
        }
        restoreInFlight = true
        defer {
            restoreInFlight = false
            isRetryingValidation = false
        }

        if state == .unknown {
            _ = prepareColdLaunch()
        }

        if case .sessionValidationFailed(let session, _) = state {
            state = .refreshing(session)
        }

        if case .refreshing(let session) = state {
            await performRefresh(session: session, reason: "restore")
            return
        }

        if state.isSessionReady {
            await SessionNetworkGate.shared.markReady()
        }
    }

    func retrySessionValidation() async {
        guard case .sessionValidationFailed(let session, _) = state else { return }
        isRetryingValidation = true
        state = .refreshing(session)
        await restoreSession()
    }

    var isValidationRetryInFlight: Bool { isRetryingValidation && restoreInFlight }

    func sessionNeedsRefresh() -> Bool {
        guard let session = state.session else { return false }
        return expiration.needsRefresh(session)
    }

    /// Blocks authenticated repositories until refresh completes (no-op when ready).
    func awaitNetworkReady() async {
        await SessionNetworkGate.shared.awaitReady()
    }

    // MARK: - Sign in / up

    func signIn(email: String, password: String) async throws {
        try await authenticate(provider: .email) {
            AuthCompletion(
                session: try await emailProvider.signIn(email: email, password: password)
            )
        }
    }

    func signUp(email: String, password: String) async throws {
        try await authenticate(provider: .email) {
            AuthCompletion(
                session: try await emailProvider.signUp(email: email, password: password)
            )
        }
    }

    func signInWithApple() async throws {
        guard let apple = appleProvider as? AppleSignInProvider else {
            throw AuthenticationError.providerUnavailable(.apple)
        }
        try await authenticate(provider: .apple) {
            let result = try await apple.signInWithResult()
            return AuthCompletion(session: result.session, firstLoginHint: result.firstLoginHint)
        }
    }

    func signInWithApple(credential: AppleIDCredentialPayload) async throws {
        guard let apple = appleProvider as? AppleSignInProvider else {
            throw AuthenticationError.providerUnavailable(.apple)
        }
        try await authenticate(provider: .apple) {
            let result = try await apple.signIn(credential: credential)
            return AuthCompletion(session: result.session, firstLoginHint: result.firstLoginHint)
        }
    }

    func signInWithGoogle() async throws {
        try await authenticate(provider: .google) {
            AuthCompletion(session: try await googleProvider.signIn())
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
        try await complete(session: session, firstLoginHint: nil)
    }

    func requestPasswordReset(email: String) async throws {
        if let error = validator.validateEmail(email) { throw error }
        try await emailProvider.requestPasswordReset(email: email)
    }

    // MARK: - Logout / lock

    func logout() async {
        emit(.logoutStarted)
        restorationGeneration &+= 1
        refreshCoordinator.cancel()
        await AuthRefreshSingleFlight.shared.bumpSessionGeneration()
        await AuthRefreshSingleFlight.shared.cancelAll()
        await SessionNetworkGate.shared.markUnauthenticated()
        await logoutCoordinator.logout()
        state = .unauthenticated
        emit(.logoutCompleted)
        AuthFlowTracer.trace("auth.session.cleared", phase: .unauthenticated, generation: restorationGeneration)
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
        _ = kind
        emit(.signInStarted(kind))
        state = .authenticating(kind)
    }

    // MARK: - Private

    private struct AuthCompletion: Sendable {
        var session: AuthenticationSession
        var firstLoginHint: OAuthFirstLoginHint?

        init(session: AuthenticationSession, firstLoginHint: OAuthFirstLoginHint? = nil) {
            self.session = session
            self.firstLoginHint = firstLoginHint
        }
    }

    private func authenticate(
        provider: AuthenticationProviderKind,
        operation: () async throws -> AuthCompletion
    ) async throws {
        state = .authenticating(provider)
        emit(.signInStarted(provider))
        defer {
            if case .authenticating = state {
                state = .unauthenticated
            }
        }
        do {
            let completion = try await operation()
            try await complete(
                session: completion.session,
                firstLoginHint: completion.firstLoginHint
            )
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

    private func complete(
        session: AuthenticationSession,
        firstLoginHint: OAuthFirstLoginHint?
    ) async throws {
        restorationGeneration &+= 1
        await AuthRefreshSingleFlight.shared.cancelAll()
        try sessionManager.install(session)
        if let sessionBootstrap {
            try await sessionBootstrap.finalize(
                session: session,
                firstLoginHint: firstLoginHint
            )
        }
        applyAuthenticated(
            session,
            event: .signInSucceeded(userID: session.userID, provider: session.provider)
        )
        await SessionNetworkGate.shared.markReady()
        refreshCoordinator.schedule(for: session)
    }

    private func applyAuthenticated(_ session: AuthenticationSession, event: AuthenticationEvent) {
        lastSessionValidationError = nil
        state = .authenticated(session)
        emit(event)
        AuthFlowTracer.traceRootTransition(to: .authenticated, generation: restorationGeneration)
    }

    private func performRefresh(session: AuthenticationSession, reason: String) async {
        emit(.tokenRefreshStarted)
        AuthFlowTracer.trace("auth.refresh.started", phase: .restoring, generation: restorationGeneration)
        AuthFlowTracer.trace("session.validation.started", phase: .restoring, generation: restorationGeneration)
        await SessionNetworkGate.shared.beginRefresh()
        let generation = restorationGeneration
        do {
            let refreshed = try await AuthRefreshSingleFlight.shared.refresh(
                fingerprint: SessionFingerprint.make(session),
                generation: generation
            ) {
                try await self.emailProvider.refresh(session: session)
            }
            guard generation == restorationGeneration else {
                traceRefreshCancelled(reason: "supersededGeneration")
                return
            }
            try sessionManager.install(refreshed)
            applyAuthenticated(refreshed, event: .tokenRefreshSucceeded)
            await SessionNetworkGate.shared.markReady()
            refreshCoordinator.schedule(for: refreshed)
            emit(.restorationSucceeded(userID: refreshed.userID))
            AuthFlowTracer.traceRefreshCompleted(.success, generation: generation)
            AuthFlowTracer.trace("session.validation.completed", phase: .authenticated, generation: generation)
        } catch let error as AuthenticationError {
            await handleRefreshFailure(error, session: session, generation: generation)
        } catch AuthBootstrapError.staleSessionResult {
            traceRefreshCancelled(reason: "staleSessionResult")
        } catch is CancellationError {
            traceRefreshCancelled(reason: "cancelled")
        } catch {
            let mapped = AuthenticationError.fromRefreshFailure(error)
            await handleRefreshFailure(mapped, session: session, generation: generation)
        }
    }

    private func handleRefreshFailure(
        _ error: AuthenticationError,
        session: AuthenticationSession,
        generation: UInt64
    ) async {
        guard generation == restorationGeneration else {
            traceRefreshCancelled(reason: "supersededGeneration")
            return
        }
        emit(.tokenRefreshFailed)
        if error.isTerminalRefreshFailure {
            AuthFlowTracer.traceRefreshCompleted(.terminalFailure, generation: generation)
            emit(.restorationFailed)
            AuthFlowTracer.trace("session.validation.completed", phase: .unauthenticated, generation: generation)
            AuthFlowTracer.traceRootTransition(to: .unauthenticated, generation: generation)
            await handleExpiredSession()
        } else if error.isTransientRefreshFailure {
            AuthFlowTracer.traceRefreshCompleted(.transientFailure, generation: generation)
            lastSessionValidationError = error
            state = .sessionValidationFailed(session, error)
            await SessionNetworkGate.shared.markUnauthenticated()
            AuthFlowTracer.trace("session.validation.completed", phase: .restoring, generation: generation)
        } else {
            AuthFlowTracer.traceRefreshCompleted(.terminalFailure, generation: generation)
            emit(.restorationFailed)
            await handleExpiredSession()
        }
    }

    private func handleProactiveRefreshFailure(_ error: AuthenticationError) async {
        emit(.tokenRefreshFailed)
        guard state.isSessionReady, let session = state.session else { return }
        let generation = restorationGeneration
        if error.isTerminalRefreshFailure {
            AuthFlowTracer.traceRefreshCompleted(.terminalFailure, generation: generation)
            await handleExpiredSession()
        } else if error.isTransientRefreshFailure {
            AuthFlowTracer.traceRefreshCompleted(.transientFailure, generation: generation)
            lastSessionValidationError = error
            state = .sessionValidationFailed(session, error)
            await SessionNetworkGate.shared.markUnauthenticated()
        }
    }

    private func handleExpiredSession() async {
        emit(.sessionExpired)
        await logout()
    }

    private func emit(_ event: AuthenticationEvent) {
        lastEvent = event
        SafeAuthLog.logEvent(event, state: state)
    }

    private func waitForRestoreCompletion() async {
        while restoreInFlight {
            await Task.yield()
        }
    }

    private func traceRestoreSessionFound(expired: Bool, present: Bool) {
        AuthFlowTracer.trace(
            "auth.restore.sessionFound expired=\(expired) present=\(present)",
            phase: expired ? .restoring : .authenticated,
            generation: restorationGeneration
        )
    }

    private func traceRefreshCancelled(reason: String) {
        AuthFlowTracer.trace(
            "auth.restore.cancelled reason=\(reason)",
            phase: .restoring,
            generation: restorationGeneration
        )
    }
}
