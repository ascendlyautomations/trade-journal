import Foundation
import OSLog

/// Bridges AuthenticationManager ↔ Navigation session phase.
///
/// Navigation remains the routing authority; this coordinator only calls
/// ``NavigationCoordinator/markAuthenticated()`` / ``markUnauthenticated()``.
///
/// Also owns **session-scoped cache invalidation** so Features never reset stores
/// on logout / account switch.
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

    init(
        authenticationManager: AuthenticationManager,
        navigation: NavigationEnvironment
    ) {
        self.authenticationManager = authenticationManager
        self.navigation = navigation
    }

    /// Cold-launch: restore credentials then align navigation.
    func bootstrapSession() async {
        await authenticationManager.restoreSession()
        syncNavigation(with: authenticationManager.state)
    }

    func signIn(email: String, password: String) async throws {
        try await authenticationManager.signIn(email: email, password: password)
        await bindAuthenticatedUser()
        navigation.coordinator.markAuthenticated()
    }

    func signUp(email: String, password: String) async throws {
        try await authenticationManager.signUp(email: email, password: password)
        await bindAuthenticatedUser()
        navigation.coordinator.markAuthenticated()
    }

    func signInWithApple() async throws {
        try await authenticationManager.signInWithApple()
        await bindAuthenticatedUser()
        navigation.coordinator.markAuthenticated()
    }

    func signInWithGoogle() async throws {
        try await authenticationManager.signInWithGoogle()
        await bindAuthenticatedUser()
        navigation.coordinator.markAuthenticated()
    }

    /// Infrastructure Continue — uses development session when allowed (Debug).
    func continueAsDevelopmentSessionIfAllowed() async throws {
        try await authenticationManager.issueDevelopmentSession()
        await bindAuthenticatedUser()
        navigation.coordinator.markAuthenticated()
    }

    func requestPasswordReset(email: String) async throws {
        try await authenticationManager.requestPasswordReset(email: email)
    }

    func logout() async {
        // Unregister while the session is still valid (BFF requires auth, with token fallback).
        if let prepareSessionTeardown {
            await prepareSessionTeardown()
        }
        await authenticationManager.logout()
        await invalidateCachesForSessionChange()
        boundUserID = nil
        navigation.coordinator.markUnauthenticated()
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
            // Cold restore / already authenticated — bind without wiping empty caches.
            if boundUserID == nil {
                boundUserID = state.session?.userID
            }
            if navigation.store.sessionPhase != .authenticated {
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
            await MainActor.run {
                onAuthenticatedSessionBound?()
            }
        }
    }

    private func invalidateCachesForSessionChange() async {
        await MainActor.run {
            invalidateSessionCaches?()
        }
    }
}
