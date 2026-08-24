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

    init(
        authenticationManager: AuthenticationManager,
        navigation: NavigationEnvironment
    ) {
        self.authenticationManager = authenticationManager
        self.navigation = navigation
    }

    /// Cold-launch: complete any deferred token refresh without blocking first paint.
    func bootstrapSession() async {
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace(
            "session.restore.started",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation
        )
        await authenticationManager.restoreSession()
        syncNavigation(with: authenticationManager.state)
        AuthFlowTracer.trace(
            "session.restore.completed",
            phase: authenticationManager.state.authFlowPhase,
            correlation: correlation
        )
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
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace("logout.started", phase: authenticationManager.state.authFlowPhase, correlation: correlation)
        if let prepareSessionTeardown {
            await prepareSessionTeardown()
        }
        await authenticationManager.logout()
        await invalidateCachesForSessionChange()
        boundUserID = nil
        navigation.coordinator.markUnauthenticated()
        AuthFlowTracer.trace("logout.completed", phase: .unauthenticated, correlation: correlation)
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
        if state.isAuthenticated {
            if boundUserID == nil {
                boundUserID = state.session?.userID
            }
            if navigation.store.sessionPhase != .authenticated {
                AuthFlowTracer.trace("root.authenticated", phase: .authenticated)
                navigation.coordinator.markAuthenticated()
            }
        } else if state != .unknown {
            if navigation.store.sessionPhase != .unauthenticated {
                navigation.coordinator.markUnauthenticated()
            }
            if boundUserID != nil {
                boundUserID = nil
                Task {
                    if let prepareSessionTeardown {
                        await prepareSessionTeardown()
                    }
                    await invalidateCachesForSessionChange()
                }
            }
        }
    }

    // MARK: - Session cache lifecycle

    private func performSignIn(operation: () async throws -> Void) async throws {
        signInGeneration &+= 1
        let generation = signInGeneration
        let correlation = AuthFlowTracer.beginCorrelation()
        AuthFlowTracer.trace("auth.signIn.started", phase: .authenticating, correlation: correlation)

        do {
            try await operation()
            guard !Task.isCancelled else {
                AuthFlowTracer.trace("auth.signIn.cancelled", phase: .unauthenticated, correlation: correlation)
                syncNavigationIfAuthenticatedAfterCancellation()
                throw CancellationError()
            }
            guard generation == signInGeneration else {
                AuthFlowTracer.trace("auth.signIn.stale", phase: authenticationManager.state.authFlowPhase, correlation: correlation)
                return
            }
            guard authenticationManager.state.isAuthenticated else {
                AuthFlowTracer.trace("auth.signIn.failed", phase: .unauthenticated, correlation: correlation)
                return
            }

            AuthFlowTracer.trace("auth.signIn.completed", phase: .authenticated, correlation: correlation)
            AuthFlowTracer.trace("auth.session.available", phase: .authenticated, correlation: correlation)
            await bindAuthenticatedUser()
            navigation.coordinator.markAuthenticated()
            AuthFlowTracer.trace("root.authenticated", phase: .authenticated, correlation: correlation)
        } catch is CancellationError {
            AuthFlowTracer.trace("auth.signIn.cancelled", phase: .unauthenticated, correlation: correlation)
            syncNavigationIfAuthenticatedAfterCancellation()
            throw CancellationError()
        } catch {
            AuthFlowTracer.trace("auth.signIn.failed", phase: .unauthenticated, correlation: correlation)
            throw error
        }
    }

    private func syncNavigationIfAuthenticatedAfterCancellation() {
        if authenticationManager.state.isAuthenticated {
            syncNavigation(with: authenticationManager.state)
        }
    }

    private func bindAuthenticatedUser() async {
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
