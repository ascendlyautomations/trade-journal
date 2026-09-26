import Foundation
import OSLog

/// Bridges AuthenticationManager ↔ Navigation session phase.
///
/// Navigation remains the routing authority; this coordinator only calls
/// ``NavigationCoordinator/markAuthenticated()`` / ``markUnauthenticated()``.
///
/// Also owns **session-scoped cache invalidation** so Features never reset stores
/// on logout / account switch.
@MainActor
final class AuthenticationCoordinator {
    private let authenticationManager: AuthenticationManager
    private let navigation: NavigationEnvironment

    /// Bound by ``CompositionRoot`` after session stores exist (MainActor).
    var invalidateSessionCaches: (@MainActor () -> Void)?
    /// Bound by ``CompositionRoot`` — best-effort push unregister after local logout (never blocks Login UI).
    var prepareSessionTeardown: (@MainActor () async -> Void)?
    /// Bound by ``CompositionRoot`` — all-device push unregister + realtime stop after server deletion.
    var prepareAccountDeletion: (@MainActor () async -> Void)?
    /// Bound by ``CompositionRoot`` — APNs registration after a user session binds.
    var onAuthenticatedSessionBound: (@MainActor () -> Void)?

    /// Last authenticated user — detects account switches without an intervening logout.
    private var boundUserID: UserID?
    /// Prevents a stale sign-in attempt from overwriting a newer success.
    private var signInGeneration: UInt64 = 0
    /// Prevents stale restore completion from publishing authenticated shell.
    private var restoreGeneration: UInt64 = 0
    /// Single-flight logout — duplicate taps must not re-enter teardown or push unregister.
    private var logoutInFlight = false

    init(
        authenticationManager: AuthenticationManager,
        navigation: NavigationEnvironment
    ) {
        self.authenticationManager = authenticationManager
        self.navigation = navigation
    }

    /// Cold-launch: async refresh only when ``prepareColdLaunch()`` left a refreshing session.
    func bootstrapSession() async {
        restoreGeneration &+= 1
        let generation = restoreGeneration
        let correlation = AuthFlowTracer.beginCorrelation()

        if authenticationManager.shouldSkipAsyncRestoreAfterColdLaunch() {
            AuthFlowTracer.trace(
                "session.restore.skipped reason=coldLaunchResolved",
                phase: authenticationManager.state.authFlowPhase,
                correlation: correlation,
                generation: generation
            )
            guard generation == restoreGeneration else {
                AuthFlowTracer.trace(
                    "auth.restore.cancelled reason=supersededBootstrap",
                    phase: authenticationManager.state.authFlowPhase,
                    correlation: correlation,
                    generation: generation
                )
                return
            }
            applyNavigation(for: authenticationManager.state, correlation: correlation)
            AuthFlowTracer.trace(
                "session.restore.completed",
                phase: authenticationManager.state.authFlowPhase,
                correlation: correlation,
                generation: generation
            )
            return
        }

        AuthFlowTracer.trace(
            "session.restore.started",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation,
            generation: generation
        )
        await authenticationManager.restoreSession()
        guard generation == restoreGeneration else {
            AuthFlowTracer.trace(
                "auth.restore.cancelled reason=supersededBootstrap",
                phase: authenticationManager.state.authFlowPhase,
                correlation: correlation,
                generation: generation
            )
            return
        }
        applyNavigation(for: authenticationManager.state, correlation: correlation)
        AuthFlowTracer.trace(
            "session.restore.completed",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation,
            generation: generation
        )
    }

    func retrySessionValidation() async {
        await authenticationManager.retrySessionValidation()
        applyNavigation(for: authenticationManager.state)
    }

    func signIn(
        email: String,
        password: String,
        smartSignUpIfNewEmail: Bool = false
    ) async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signIn(
                email: email,
                password: password,
                smartSignUpIfNewEmail: smartSignUpIfNewEmail
            )
        })
    }

    func signUp(email: String, password: String, fullName: String? = nil) async throws {
        let hint = ProfileDisplayNamePolicy.normalized(fullName).map {
            OAuthFirstLoginHint(fullName: $0, email: nil)
        }
        try await performSignIn(operation: {
            try await self.authenticationManager.signUp(
                email: email,
                password: password,
                firstLoginHint: hint
            )
        })
    }

    func signInWithApple() async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signInWithApple()
        })
    }

    func signInWithApple(credential: AppleIDCredentialPayload) async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signInWithApple(credential: credential)
        })
    }

    func signInWithGoogle() async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signInWithGoogle()
        })
    }

    /// Infrastructure Continue — uses development session when allowed (Debug).
    func continueAsDevelopmentSessionIfAllowed() async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.issueDevelopmentSession()
        })
    }

    func requestPasswordReset(email: String) async throws {
        await AppLaunchController.shared.ensureFullBootstrapComplete()
        try await authenticationManager.requestPasswordReset(email: email)
    }

    func resendSignupConfirmation(email: String) async throws {
        try await authenticationManager.resendSignupConfirmation(email: email)
    }

    func logout() async {
        await performLocalSessionTeardown(
            correlationLabel: "logout",
            useAccountDeletionTeardown: false
        )
    }

    /// Server-side account deletion only — local teardown runs after the user confirms on the success screen.
    func deleteAuthenticatedAccountOnServer(using repository: any AccountRepository) async throws {
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace(
            "accountDeletion.started",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation
        )

        try await repository.deleteAuthenticatedAccount()

        AuthFlowTracer.trace(
            "accountDeletion.serverConfirmed",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation
        )
    }

    /// Clears session, caches, and routes to Sign In after account deletion success.
    func finishAccountDeletionAndReturnToSignIn() async {
        await performLocalSessionTeardown(
            correlationLabel: "accountDeletion",
            useAccountDeletionTeardown: true
        )
    }

    /// Deletes the authenticated account on the server, then clears all local session state.
    func deleteAccount(using repository: any AccountRepository) async throws {
        try await deleteAuthenticatedAccountOnServer(using: repository)
        await finishAccountDeletionAndReturnToSignIn()
    }

    private func performLocalSessionTeardown(
        correlationLabel: String,
        useAccountDeletionTeardown: Bool
    ) async {
        guard !logoutInFlight else { return }
        logoutInFlight = true
        defer { logoutInFlight = false }

        restoreGeneration &+= 1
        let generation = restoreGeneration
#if DEBUG
        LogoutTrace.tap(generation: generation)
#endif
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace(
            "\(correlationLabel).started",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation,
            generation: generation
        )

        if useAccountDeletionTeardown {
#if DEBUG
            AccountDeletionDebugLog.localTeardownStarted()
#endif
        }

        await authenticationManager.logout()
#if DEBUG
        LogoutTrace.generationInvalidated(elapsedMs: LogoutTrace.elapsedSinceTapMs())
#endif

        invalidateCachesForSessionChange()
#if DEBUG
        LogoutTrace.localSessionCleared(elapsedMs: LogoutTrace.elapsedSinceTapMs())
#endif

        boundUserID = nil
        navigation.clearDeferredAuthenticatedSnapshot()
        navigation.clearPersistedState()
        navigation.coordinator.markUnauthenticated()
        applyNavigation(for: authenticationManager.state, correlation: correlation)
#if DEBUG
        LogoutTrace.loginPresented(elapsedMs: LogoutTrace.elapsedSinceTapMs())
#endif

        let pushTeardown = prepareSessionTeardown
        let accountDeletionTeardown = prepareAccountDeletion
        Task { @MainActor in
            if useAccountDeletionTeardown, let accountDeletionTeardown {
                await accountDeletionTeardown()
            } else if let pushTeardown {
#if DEBUG
                LogoutTrace.pushUnregisterStarted(background: true)
#endif
                await pushTeardown()
#if DEBUG
                LogoutTrace.pushUnregisterCompleted(outcome: "finished")
#endif
            }
        }

        AuthFlowTracer.trace(
            "\(correlationLabel).completed",
            phase: .unauthenticated,
            correlation: correlation,
            generation: generation
        )
    }

    /// Authenticated session email when present (nil for development bypass).
    var sessionEmail: String? {
        authenticationManager.state.session?.email
    }

    /// Primary sign-in provider for the active session (used by account deletion copy).
    var currentSignInProvider: AuthenticationProviderKind? {
        authenticationManager.state.session?.provider
    }

    func recoverSessionAfterUnauthorized() async -> NetworkUnauthorizedRecovery.Outcome {
        switch await authenticationManager.attemptRefreshAfterUnauthorized() {
        case .refreshed:
            return .recovered
        case .transientFailure:
            return .failedTransient
        case .sessionTerminated:
            return .sessionEnded
        }
    }

    func handleUnauthorizedFromNetwork() async {
        _ = await recoverSessionAfterUnauthorized()
    }

    func syncNavigation(with state: AuthenticationState) {
        _ = state
        applyNavigation(for: authenticationManager.state)
    }

    // MARK: - Session cache lifecycle

    private func applyNavigation(for state: AuthenticationState, correlation: String? = nil) {
        let bootstrapAllowed = state.allowsAuthenticatedExperience
        AuthFlowTracer.traceBootstrapAllowed(
            bootstrapAllowed,
            authPhase: state.authFlowPhase,
            generation: authenticationManager.restorationGeneration
        )

        switch state {
        case .authenticated, .locked:
            if navigation.store.sessionPhase != .authenticated {
                AuthFlowTracer.trace(
                    "root.authenticated",
                    phase: .authenticated,
                    correlation: correlation,
                    generation: authenticationManager.restorationGeneration
                )
                let deferred = navigation.consumeDeferredAuthenticatedSnapshot()
                navigation.coordinator.markAuthenticated(applyingDeferred: deferred)
            }
            Task { await bindAuthenticatedUser() }

        case .sessionValidationFailed(let session, _):
            if navigation.store.sessionPhase != .authenticated {
                let deferred = navigation.consumeDeferredAuthenticatedSnapshot()
                navigation.coordinator.markAuthenticated(applyingDeferred: deferred)
            }
            if boundUserID == nil {
                boundUserID = session.userID
            }

        case .refreshing:
            if navigation.store.sessionPhase != .authenticated, boundUserID != nil {
                let deferred = navigation.consumeDeferredAuthenticatedSnapshot()
                navigation.coordinator.markAuthenticated(applyingDeferred: deferred)
            }

        case .unknown:
            break

        case .unauthenticated, .failure, .authenticating:
            if navigation.store.sessionPhase != .unauthenticated {
                navigation.coordinator.markUnauthenticated()
            }
            navigation.clearDeferredAuthenticatedSnapshot()
            if boundUserID != nil {
                boundUserID = nil
                let epoch = SessionViewerGate.shared.epoch
                Task { @MainActor in
                    guard SessionViewerGate.shared.epoch == epoch else { return }
                    invalidateCachesForSessionChange()
                }
            }
            if case .unauthenticated = state {
                navigation.clearPersistedState()
            }
        }
    }

    private func performSignIn(operation: () async throws -> Void) async throws {
        await AppLaunchController.shared.ensureFullBootstrapComplete()
        signInGeneration &+= 1
        restoreGeneration &+= 1
        let generation = signInGeneration
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace(
            "auth.signIn.started",
            phase: .authenticating,
            correlation: correlation,
            generation: generation
        )

        do {
            try await operation()
            guard !Task.isCancelled else {
                AuthFlowTracer.trace(
                    "auth.signIn.cancelled",
                    phase: .unauthenticated,
                    correlation: correlation,
                    generation: generation
                )
                syncNavigationIfAuthenticatedAfterCancellation()
                throw CancellationError()
            }
            guard generation == signInGeneration else {
                AuthFlowTracer.trace(
                    "auth.signIn.stale",
                    phase: authenticationManager.state.authFlowPhase,
                    correlation: correlation,
                    generation: generation
                )
                if authenticationManager.state.isSessionReady {
                    await bindAuthenticatedUser()
                    navigation.coordinator.markAuthenticated(
                        applyingDeferred: navigation.consumeDeferredAuthenticatedSnapshot()
                    )
                }
                return
            }
            guard authenticationManager.state.isSessionReady else {
                AuthFlowTracer.trace(
                    "auth.signIn.failed",
                    phase: .unauthenticated,
                    correlation: correlation,
                    generation: generation
                )
                return
            }

            AuthFlowTracer.trace(
                "auth.signIn.completed",
                phase: .authenticated,
                correlation: correlation,
                generation: generation
            )
            AuthFlowTracer.trace(
                "auth.session.available",
                phase: .authenticated,
                correlation: correlation,
                generation: generation
            )
            await bindAuthenticatedUser()
            navigation.coordinator.markAuthenticated(
                applyingDeferred: navigation.consumeDeferredAuthenticatedSnapshot()
            )
            AuthFlowTracer.trace(
                "root.authenticated",
                phase: .authenticated,
                correlation: correlation,
                generation: generation
            )
        } catch is CancellationError {
            AuthFlowTracer.trace(
                "auth.signIn.cancelled",
                phase: .unauthenticated,
                correlation: correlation,
                generation: generation
            )
            syncNavigationIfAuthenticatedAfterCancellation()
            throw CancellationError()
        } catch {
            AuthFlowTracer.trace(
                "auth.signIn.failed",
                phase: .unauthenticated,
                correlation: correlation,
                generation: generation
            )
            throw error
        }
    }

    private func syncNavigationIfAuthenticatedAfterCancellation() {
        if authenticationManager.state.isSessionReady {
            syncNavigation(with: authenticationManager.state)
        }
    }

    private func bindAuthenticatedUser() async {
        guard authenticationManager.state.isSessionReady else { return }
        let newID = authenticationManager.state.session?.userID
        let switchedAccounts = boundUserID != nil && newID != nil && boundUserID != newID
        if switchedAccounts {
            invalidateCachesForSessionChange()
        }
        if let newID {
            SessionViewerGate.shared.bind(newID.rawValue)
        }
        let isNewBind = boundUserID == nil && newID != nil
        boundUserID = newID
        if isNewBind || switchedAccounts {
            AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
            if authenticationManager.state.session?.provider == .google {
                AppLog.authentication.info("OAuth authenticated session bound")
            }
            AppLog.authentication.info(
                "Authenticated session bound newBind=\(isNewBind, privacy: .public) switched=\(switchedAccounts, privacy: .public)"
            )
            #if DEBUG
            if isNewBind {
                SupabaseSessionUsage.beginSession()
            }
            #endif
            onAuthenticatedSessionBound?()
        }
    }

    private func invalidateCachesForSessionChange() {
        invalidateSessionCaches?()
    }
}
