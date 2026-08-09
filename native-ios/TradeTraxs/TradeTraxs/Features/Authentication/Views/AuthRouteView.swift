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
        case .choosePlan:
            AuthPlanPlaceholderView(
                title: "Choose your plan",
                message: "Plan selection arrives with Billing. Continue to sign in for now.",
                navigationCoordinator: navigationCoordinator
            )
        case .finishTrial:
            AuthPlanPlaceholderView(
                title: "Finish your trial",
                message: "Trial checkout arrives with Billing. Continue to sign in for now.",
                navigationCoordinator: navigationCoordinator
            )
        }
    }
}
