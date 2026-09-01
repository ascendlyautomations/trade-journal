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
    /// Bound by ``CompositionRoot`` — await push unregister **before** clearing auth.
    var prepareSessionTeardown: (@MainActor () async -> Void)?
    /// Bound by ``CompositionRoot`` — APNs registration after a user session binds.
    var onAuthenticatedSessionBound: (@MainActor () -> Void)?

    /// Last authenticated user — detects account switches without an intervening logout.
    private var boundUserID: UserID?
    /// Prevents a stale sign-in attempt from overwriting a newer success.
    private var signInGeneration: UInt64 = 0
    /// Prevents stale restore completion from publishing authenticated shell.
    private var restoreGeneration: UInt64 = 0

    init(
        authenticationManager: AuthenticationManager,
        navigation: NavigationEnvironment
    ) {
        self.authenticationManager = authenticationManager
        self.navigation = navigation
    }

    /// Cold-launch: validate/refresh session before entering authenticated shell.
    func bootstrapSession() async {
        restoreGeneration &+= 1
        let generation = restoreGeneration
        let correlation = AuthFlowTracer.beginCorrelation()
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

    func signIn(email: String, password: String) async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signIn(email: email, password: password)
        })
    }

    func signUp(email: String, password: String) async throws {
        try await performSignIn(operation: {
            try await self.authenticationManager.signUp(email: email, password: password)
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
        try await authenticationManager.requestPasswordReset(email: email)
    }

    func logout() async {
        restoreGeneration &+= 1
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace(
            "logout.started",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation,
            generation: restoreGeneration
        )
        if let prepareSessionTeardown {
            await prepareSessionTeardown()
        }
        await authenticationManager.logout()
        await invalidateCachesForSessionChange()
        boundUserID = nil
        navigation.clearDeferredAuthenticatedSnapshot()
        navigation.clearPersistedState()
        navigation.coordinator.markUnauthenticated()
        AuthFlowTracer.trace(
            "logout.completed",
            phase: .unauthenticated,
            correlation: correlation,
            generation: restoreGeneration
        )
    }

    /// Authenticated session email when present (nil for development bypass).
    var sessionEmail: String? {
        authenticationManager.state.session?.email
    }

    func handleUnauthorizedFromNetwork() async {
        AppLog.authentication.info("Unauthorized — forcing logout")
        await logout()
    }

    func syncNavigation(with state: AuthenticationState) {
        _ = state
        applyNavigation(for: authenticationManager.state)
    }

    // MARK: - Session cache lifecycle

    private func applyNavigation(for state: AuthenticationState, correlation: String? = nil) {
        let bootstrapAllowed = state.isSessionReady
        AuthFlowTracer.traceBootstrapAllowed(
            bootstrapAllowed,
            generation: authenticationManager.restorationGeneration
        )

        switch state {
        case .authenticated, .locked:
            if boundUserID == nil {
                boundUserID = state.session?.userID
            }
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

        case .sessionValidationFailed, .refreshing, .unknown:
            if navigation.store.sessionPhase == .authenticated {
                navigation.coordinator.markUnauthenticated()
            }

        case .unauthenticated, .failure, .authenticating:
            if navigation.store.sessionPhase != .unauthenticated {
                navigation.coordinator.markUnauthenticated()
            }
            navigation.clearDeferredAuthenticatedSnapshot()
            if boundUserID != nil {
                boundUserID = nil
                Task {
                    if let prepareSessionTeardown {
                        await prepareSessionTeardown()
                    }
                    await invalidateCachesForSessionChange()
                }
            }
            if case .unauthenticated = state {
                navigation.clearPersistedState()
            }
        }
    }

    private func performSignIn(operation: () async throws -> Void) async throws {
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
            await invalidateCachesForSessionChange()
        }
        let isNewBind = boundUserID == nil && newID != nil
        boundUserID = newID
        if isNewBind || switchedAccounts {
            #if DEBUG
            if isNewBind {
                SupabaseSessionUsage.beginSession()
            }
            #endif
            onAuthenticatedSessionBound?()
        }
    }

    private func invalidateCachesForSessionChange() async {
        invalidateSessionCaches?()
    }
}
