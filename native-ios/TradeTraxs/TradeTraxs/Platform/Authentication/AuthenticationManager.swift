import Foundation
import OSLog

enum UnauthorizedRefreshResult: Sendable {
    case refreshed
    case transientFailure
    case sessionTerminated
}

/// Owns authentication state. Features observe ``state`` — they never touch Keychain.
@Observable
final class AuthenticationManager {
    private(set) var state: AuthenticationState = .unknown
    private(set) var lastEvent: AuthenticationEvent?
    /// Monotonic attempt id — stale async refresh/restore completions must not publish state.
    private(set) var restorationGeneration: UInt64 = 0
    /// Set after synchronous Keychain restore in ``prepareColdLaunch()``.
    private(set) var coldLaunchKeychainRestoreCompleted = false

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

    /// Best-effort Apple authorization code registration (BFF stores refresh token for deletion revoke).
    @ObservationIgnored var appleRevocationCredentialHandler: (@Sendable (String) async -> Void)?

    private(set) var lastSessionValidationError: AuthenticationError?

    private var restoreInFlight = false
    private var isRetryingValidation = false
    private var logoutInFlight = false

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
        UnauthLaunchProbe.sessionCheckStarted()
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            coldLaunchKeychainRestoreCompleted = true
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
            UnauthLaunchProbe.mainThreadSlow(operation: "auth.prepareColdLaunch", durationMs: ms)
        }
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
                UnauthLaunchProbe.noSession()
                Task { await SessionNetworkGate.shared.markUnauthenticated() }
                return state
            }
            let expired = expiration.isExpired(session) || expiration.needsRefresh(session)
            traceRestoreSessionFound(expired: expired, present: true)
            if expiration.needsRefresh(session) {
                // Keychain-only: mark refresh required — ``restoreSession()`` performs the single network refresh.
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

    /// Async follow-up after cold launch — refresh only when required.
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

        if !coldLaunchKeychainRestoreCompleted, state == .unknown {
            _ = prepareColdLaunch()
        }

        if coldLaunchKeychainRestoreCompleted {
            switch state {
            case .unauthenticated, .failure:
                await SessionNetworkGate.shared.markUnauthenticated()
                return
            case .authenticated, .locked:
                await SessionNetworkGate.shared.markReady()
                return
            case .sessionValidationFailed:
                return
            case .authenticating:
                return
            case .unknown, .refreshing:
                break
            }
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

    /// True when ``prepareColdLaunch()`` already resolved session state (no second Keychain read).
    func shouldSkipAsyncRestoreAfterColdLaunch() -> Bool {
        guard coldLaunchKeychainRestoreCompleted else { return false }
        switch state {
        case .refreshing, .unknown:
            return false
        case .unauthenticated, .failure, .authenticated, .locked, .sessionValidationFailed, .authenticating:
            return true
        }
    }

    func retrySessionValidation() async {
        guard case .sessionValidationFailed(let session, _) = state else { return }
        isRetryingValidation = true
        state = .refreshing(session)
        await restoreSession()
    }

    /// Invoked when an authenticated API returns 401 — refresh once, then terminal logout if needed.
    func attemptRefreshAfterUnauthorized() async -> UnauthorizedRefreshResult {
        if case .sessionValidationFailed = state {
            return .transientFailure
        }
        if case .authenticated = state, sessionManager.accessToken?.isEmpty != false {
            return .transientFailure
        }
        if restoreInFlight {
            await waitForRestoreCompletion()
            if state.isSessionReady {
                return .refreshed
            }
        }

        switch state {
        case .unauthenticated, .failure, .unknown, .authenticating:
            return .sessionTerminated
        case .sessionValidationFailed:
            return .transientFailure
        case .refreshing:
            await waitForRestoreCompletion()
            return state.isSessionReady ? .refreshed : .transientFailure
        case .authenticated, .locked:
            break
        }

        guard let session = state.session else {
            return .sessionTerminated
        }

        let generation = restorationGeneration
        do {
            let refreshed = try await AuthRefreshSingleFlight.shared.refresh(
                fingerprint: SessionFingerprint.make(session),
                generation: generation
            ) {
                try await self.emailProvider.refresh(session: session)
            }
            guard generation == restorationGeneration else {
                return .transientFailure
            }
            try sessionManager.install(refreshed)
            await SessionNetworkGate.shared.markReady()
            applyAuthenticated(refreshed, event: .tokenRefreshSucceeded)
            refreshCoordinator.schedule(for: refreshed)
            return .refreshed
        } catch let error as AuthenticationError {
            if error.isTerminalRefreshFailure {
                await handleExpiredSession()
                return .sessionTerminated
            }
            if error.isTransientRefreshFailure {
                lastSessionValidationError = error
                state = .sessionValidationFailed(session, error)
                await SessionNetworkGate.shared.markUnauthenticated()
                return .transientFailure
            }
            await handleExpiredSession()
            return .sessionTerminated
        } catch is CancellationError {
            return .transientFailure
        } catch {
            let mapped = AuthenticationError.fromRefreshFailure(error)
            if mapped.isTerminalRefreshFailure {
                await handleExpiredSession()
                return .sessionTerminated
            }
            if mapped.isTransientRefreshFailure {
                lastSessionValidationError = mapped
                state = .sessionValidationFailed(session, mapped)
                await SessionNetworkGate.shared.markUnauthenticated()
                return .transientFailure
            }
            await handleExpiredSession()
            return .sessionTerminated
        }
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

    func signIn(email: String, password: String, smartSignUpIfNewEmail: Bool = false) async throws {
        if smartSignUpIfNewEmail {
            try await signInOfferingSignUpForUnknownAccount(email: email, password: password)
            return
        }
        try await authenticate(provider: .email) {
            AuthCompletion(
                session: try await emailProvider.signIn(email: email, password: password)
            )
        }
    }

    /// Sign-in first; on authoritative invalid-credentials only, attempt existing sign-up flow.
    /// Wrong password for an existing account is resolved when sign-up returns ``emailAlreadyRegistered``.
    private func signInOfferingSignUpForUnknownAccount(email: String, password: String) async throws {
        do {
            try await authenticate(provider: .email) {
                AuthCompletion(
                    session: try await emailProvider.signIn(email: email, password: password)
                )
            }
        } catch AuthenticationError.invalidCredentials {
            do {
                try await signUp(email: email, password: password)
            } catch AuthenticationError.emailAlreadyRegistered {
                throw AuthenticationError.invalidCredentials
            }
        }
    }

    func signUp(
        email: String,
        password: String,
        firstLoginHint: OAuthFirstLoginHint? = nil
    ) async throws {
        try await authenticate(provider: .email) {
            AuthCompletion(
                session: try await emailProvider.signUp(
                    email: email,
                    password: password,
                    fullName: firstLoginHint?.fullName
                ),
                firstLoginHint: firstLoginHint
            )
        }
    }

    func signInWithApple() async throws {
        try await performOAuthSignIn(provider: .apple) {
            guard let apple = appleProvider as? AppleSignInProvider else {
                throw AuthenticationError.providerUnavailable(.apple)
            }
            try await authenticate(provider: .apple) {
                let result = try await apple.signInWithResult()
                return AuthCompletion(
                    session: result.session,
                    firstLoginHint: result.firstLoginHint,
                    appleAuthorizationCode: result.authorizationCode
                )
            }
        }
    }

    func signInWithApple(credential: AppleIDCredentialPayload) async throws {
        try await performOAuthSignIn(provider: .apple) {
            guard let apple = appleProvider as? AppleSignInProvider else {
#if DEBUG
                AppLog.authentication.debug(
                    "[AppleAuth] manager.rejected providerType=\(String(describing: type(of: self.appleProvider)), privacy: .public)"
                )
#endif
                throw AuthenticationError.providerUnavailable(.apple)
            }
            try await authenticate(provider: .apple) {
                let result = try await apple.signIn(credential: credential)
                return AuthCompletion(
                    session: result.session,
                    firstLoginHint: result.firstLoginHint,
                    appleAuthorizationCode: credential.authorizationCode
                )
            }
        }
    }

    func signInWithGoogle() async throws {
        try await performOAuthSignIn(provider: .google) {
            try await authenticate(provider: .google) {
                AuthCompletion(session: try await googleProvider.signIn())
            }
        }
    }

    private func performOAuthSignIn(
        provider: AuthenticationProviderKind,
        operation: () async throws -> Void
    ) async throws {
        guard await OAuthSignInSingleFlight.shared.tryBegin(provider) else {
            throw AuthenticationError.cancelled
        }
        do {
            try await operation()
        } catch {
            await OAuthSignInSingleFlight.shared.end(provider)
            throw error
        }
        await OAuthSignInSingleFlight.shared.end(provider)
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

    func resendSignupConfirmation(email: String) async throws {
        if let error = validator.validateEmail(email) { throw error }
        try await emailProvider.resendSignupConfirmation(email: email)
    }

    // MARK: - Logout / lock

    func logout() async {
        guard !logoutInFlight else { return }
        logoutInFlight = true
        defer { logoutInFlight = false }

        emit(.logoutStarted)
        restorationGeneration &+= 1
        refreshCoordinator.cancel()
        await AuthRefreshSingleFlight.shared.bumpSessionGeneration()
        await AuthRefreshSingleFlight.shared.cancelAll()
        await SessionNetworkGate.shared.markUnauthenticated()
        lastSessionValidationError = nil

        let remoteSession = logoutCoordinator.performLocalTeardown()

        state = .unauthenticated
        AuthFlowTracer.trace("auth.session.cleared", phase: .unauthenticated, generation: restorationGeneration)
        emit(.logoutCompleted)

        if let remoteSession {
            Task {
                await self.logoutCoordinator.signOutRemotely(session: remoteSession)
            }
        }
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
        var appleAuthorizationCode: String?

        init(
            session: AuthenticationSession,
            firstLoginHint: OAuthFirstLoginHint? = nil,
            appleAuthorizationCode: String? = nil
        ) {
            self.session = session
            self.firstLoginHint = firstLoginHint
            self.appleAuthorizationCode = appleAuthorizationCode
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
            if provider == .apple, let code = completion.appleAuthorizationCode {
                let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let handler = appleRevocationCredentialHandler {
                    Task { await handler(trimmed) }
                }
            }
        } catch is CancellationError {
            if case .authenticating = state {
                state = .unauthenticated
            }
            emit(.signInFailed(.cancelled))
            throw CancellationError()
        } catch let error as AuthenticationError {
            if case .emailConfirmationRequired = error {
                state = .unauthenticated
                throw error
            }
#if DEBUG
            if provider == .apple {
                AppLog.authentication.debug(
                    "[AppleAuth] authenticate.failed errorType=AuthenticationError error=\(String(describing: error), privacy: .public)"
                )
            }
#endif
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
        let mergedHint = OAuthFirstLoginHint.merged(explicit: firstLoginHint, session: session)
        if let sessionBootstrap {
            try await sessionBootstrap.finalize(
                session: session,
                firstLoginHint: mergedHint?.hasContent == true ? mergedHint : nil
            )
        }
        await MainActor.run {
            OAuthProfileOnboardingNameStore.bindEmailPendingToUserIfNeeded(
                email: session.email,
                userID: session.userID
            )
            if let manual = ProfileDisplayNamePolicy.normalized(firstLoginHint?.fullName),
               session.provider == .email
            {
                OAuthProfileOnboardingNameStore.stageManualSignup(fullName: manual, for: session.userID)
            } else if let manual = ProfileDisplayNamePolicy.normalized(firstLoginHint?.fullName) {
                OAuthProfileOnboardingNameStore.stageProvider(fullName: manual, for: session.userID)
            } else if let mergedName = ProfileDisplayNamePolicy.normalized(mergedHint?.fullName) {
                if session.provider == .email {
                    OAuthProfileOnboardingNameStore.stageManualSignup(fullName: mergedName, for: session.userID)
                } else {
                    OAuthProfileOnboardingNameStore.stageProvider(fullName: mergedName, for: session.userID)
                }
            }
        }
        await SessionNetworkGate.shared.markReady()
        applyAuthenticated(
            session,
            event: .signInSucceeded(userID: session.userID, provider: session.provider)
        )
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
        AuthRestoreDebug.refreshStarted(generation: generation)
        let refreshStartedAt = CFAbsoluteTimeGetCurrent()
        do {
            let refreshed = try await AuthSessionRefreshTimeout.run(configuration: configuration) {
                try await AuthRefreshSingleFlight.shared.refresh(
                    fingerprint: SessionFingerprint.make(session),
                    generation: generation
                ) {
                    try await self.emailProvider.refresh(session: session)
                }
            }
            guard generation == restorationGeneration else {
                traceRefreshCancelled(reason: "supersededGeneration")
                return
            }
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - refreshStartedAt) * 1_000)
            try sessionManager.install(refreshed)
            AuthRefreshTiming.sessionPersisted(generation: generation)
            await SessionNetworkGate.shared.markReady()
            applyAuthenticated(refreshed, event: .tokenRefreshSucceeded)
            AuthRestoreDebug.refreshSucceeded(durationMs: durationMs, generation: generation)
            AuthRestoreDebug.routeAuthenticated(generation: generation)
            refreshCoordinator.schedule(for: refreshed)
            emit(.restorationSucceeded(userID: refreshed.userID))
            AuthFlowTracer.traceRefreshCompleted(.success, generation: generation)
            AuthFlowTracer.trace("session.validation.completed", phase: .authenticated, generation: generation)
        } catch let error as AuthenticationError {
            await handleRefreshFailure(
                error,
                session: session,
                generation: generation,
                durationMs: Int((CFAbsoluteTimeGetCurrent() - refreshStartedAt) * 1_000)
            )
        } catch AuthBootstrapError.staleSessionResult {
            traceRefreshCancelled(reason: "staleSessionResult")
        } catch is CancellationError {
            await handleRefreshInterrupted(
                session: session,
                generation: generation,
                reason: "cancelled",
                durationMs: Int((CFAbsoluteTimeGetCurrent() - refreshStartedAt) * 1_000)
            )
        } catch {
            let mapped = AuthenticationError.fromRefreshFailure(error)
            await handleRefreshFailure(
                mapped,
                session: session,
                generation: generation,
                durationMs: Int((CFAbsoluteTimeGetCurrent() - refreshStartedAt) * 1_000)
            )
        }
    }

    private func handleRefreshFailure(
        _ error: AuthenticationError,
        session: AuthenticationSession,
        generation: UInt64,
        durationMs: Int
    ) async {
        guard generation == restorationGeneration else {
            traceRefreshCancelled(reason: "supersededGeneration")
            return
        }
        emit(.tokenRefreshFailed)
        if isRefreshTimeout(error) {
            AuthRestoreDebug.refreshTimedOut(durationMs: durationMs, generation: generation)
        }
        if error.isTerminalRefreshFailure {
            AuthRestoreDebug.refreshFailed(
                classification: "terminal",
                durationMs: durationMs,
                generation: generation
            )
            AuthRestoreDebug.routeUnauthenticated(generation: generation)
            AuthFlowTracer.traceRefreshCompleted(.terminalFailure, generation: generation)
            emit(.restorationFailed)
            AuthFlowTracer.trace("session.validation.completed", phase: .unauthenticated, generation: generation)
            AuthFlowTracer.traceRootTransition(to: .unauthenticated, generation: generation)
            await handleExpiredSession()
        } else if error.isTransientRefreshFailure {
            await invalidateStaleRefreshAttempt(activeGeneration: generation)
            AuthRestoreDebug.refreshFailed(
                classification: "transient",
                durationMs: durationMs,
                generation: generation
            )
            AuthRestoreDebug.routeRecoverableFailure(generation: generation)
            AuthFlowTracer.traceRefreshCompleted(.transientFailure, generation: generation)
            lastSessionValidationError = error
            state = .sessionValidationFailed(session, error)
            await SessionNetworkGate.shared.markUnauthenticated()
            AuthFlowTracer.trace("session.validation.completed", phase: .restoring, generation: generation)
        } else {
            AuthRestoreDebug.refreshFailed(
                classification: "terminal",
                durationMs: durationMs,
                generation: generation
            )
            AuthRestoreDebug.routeUnauthenticated(generation: generation)
            AuthFlowTracer.traceRefreshCompleted(.terminalFailure, generation: generation)
            emit(.restorationFailed)
            await handleExpiredSession()
        }
    }

    private func handleRefreshInterrupted(
        session: AuthenticationSession,
        generation: UInt64,
        reason: String,
        durationMs: Int
    ) async {
        traceRefreshCancelled(reason: reason)
        guard generation == restorationGeneration else { return }
        guard case .refreshing = state else { return }
        let transient = AuthenticationError.unknown("refreshTimeout")
        await handleRefreshFailure(
            transient,
            session: session,
            generation: generation,
            durationMs: durationMs
        )
    }

    private func isRefreshTimeout(_ error: AuthenticationError) -> Bool {
        if case .unknown(let reason) = error, reason == "refreshTimeout" {
            return true
        }
        return false
    }

    /// Cancels in-flight refresh work and bumps generation so late HTTP completion cannot publish auth state.
    private func invalidateStaleRefreshAttempt(activeGeneration: UInt64) async {
        guard activeGeneration == restorationGeneration else { return }
        restorationGeneration &+= 1
        refreshCoordinator.cancel()
        await AuthRefreshSingleFlight.shared.bumpSessionGeneration()
        await AuthRefreshSingleFlight.shared.cancelAll()
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
        if present {
            AuthRestoreDebug.persistedSessionLoaded(expired: expired, generation: restorationGeneration)
        }
    }

    private func traceRefreshCancelled(reason: String) {
        AuthFlowTracer.trace(
            "auth.restore.cancelled reason=\(reason)",
            phase: .restoring,
            generation: restorationGeneration
        )
    }
}
