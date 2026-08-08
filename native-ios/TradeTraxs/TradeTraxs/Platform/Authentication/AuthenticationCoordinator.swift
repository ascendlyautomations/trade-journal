import Foundation
import OSLog

/// Bridges AuthenticationManager ↔ Navigation session phase.
///
/// Navigation remains the routing authority; this coordinator only calls
/// ``NavigationCoordinator/markAuthenticated()`` / ``markUnauthenticated()``.
final class AuthenticationCoordinator {
    private let authenticationManager: AuthenticationManager
    private let navigation: NavigationEnvironment

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
        navigation.coordinator.markAuthenticated()
    }

    func signUp(email: String, password: String) async throws {
        try await authenticationManager.signUp(email: email, password: password)
        navigation.coordinator.markAuthenticated()
    }

    func signInWithApple() async throws {
        try await authenticationManager.signInWithApple()
        navigation.coordinator.markAuthenticated()
    }

    func signInWithGoogle() async throws {
        try await authenticationManager.signInWithGoogle()
        navigation.coordinator.markAuthenticated()
    }

    /// Infrastructure Continue — uses development session when allowed (Debug).
    func continueAsDevelopmentSessionIfAllowed() async throws {
        try await authenticationManager.issueDevelopmentSession()
        navigation.coordinator.markAuthenticated()
    }

    func logout() async {
        await authenticationManager.logout()
        navigation.coordinator.markUnauthenticated()
    }

    func handleUnauthorizedFromNetwork() async {
        AppLog.authentication.info("Unauthorized — forcing logout")
        await logout()
    }

    func syncNavigation(with state: AuthenticationState) {
        if state.isAuthenticated {
            if navigation.store.sessionPhase != .authenticated {
                navigation.coordinator.markAuthenticated()
            }
        } else if state != .unknown {
            if navigation.store.sessionPhase != .unauthenticated {
                navigation.coordinator.markUnauthenticated()
            }
        }
    }
}
