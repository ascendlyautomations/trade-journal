import SwiftUI

/// Maps ``AuthRoute`` → production authentication screens.
struct AuthRouteView: View {
    let route: AuthRoute
    let navigationCoordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    let allowsDevelopmentBypass: Bool

    var body: some View {
        switch route {
        case .login:
            LoginView(
                authenticationCoordinator: authenticationCoordinator,
                navigationCoordinator: navigationCoordinator,
                allowsDevelopmentBypass: allowsDevelopmentBypass
            )
        case .resetPassword:
            ResetPasswordView(authenticationCoordinator: authenticationCoordinator)
        case .onboarding:
            OnboardingView(navigationCoordinator: navigationCoordinator)
        case .choosePlan, .finishTrial:
            LoginView(
                authenticationCoordinator: authenticationCoordinator,
                navigationCoordinator: navigationCoordinator,
                allowsDevelopmentBypass: allowsDevelopmentBypass
            )
        }
    }
}
