import SwiftUI

/// Minimal route-aware surfaces used while feature modules are unimplemented.
///
/// These are **not** product screens. They prove the production navigation
/// framework (tabs, stacks, sheets, covers) without building features.
/// Feature modules replace the bodies later — not the navigation architecture.

struct NavigationInfrastructurePlaceholder: View {
    let title: String
    let subtitle: String
    var systemImage: String = "square.dashed"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(subtitle)
        }
    }
}

struct AuthInfrastructureView: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    @Bindable var authenticationManager: AuthenticationManager

    var body: some View {
        NavigationStack(path: authPath) {
            AuthRoutePlaceholder(
                route: .login,
                coordinator: coordinator,
                authenticationCoordinator: authenticationCoordinator,
                authenticationManager: authenticationManager
            )
            .navigationDestination(for: AuthRoute.self) { route in
                AuthRoutePlaceholder(
                    route: route,
                    coordinator: coordinator,
                    authenticationCoordinator: authenticationCoordinator,
                    authenticationManager: authenticationManager
                )
            }
        }
    }

    private var authPath: Binding<[AuthRoute]> {
        Binding(
            get: { store.paths.auth },
            set: { store.paths.auth = $0 }
        )
    }
}

private struct AuthRoutePlaceholder: View {
    let route: AuthRoute
    let coordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    @Bindable var authenticationManager: AuthenticationManager
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            NavigationInfrastructurePlaceholder(
                title: authTitle(route),
                subtitle: "Authentication platform — feature UI arrives later.",
                systemImage: "person.badge.key"
            )

            if let statusMessage {
                Text(statusMessage)
                    .experienceStyle(.footnote, color: ExperienceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ExperienceSpacing.xl)
            }

            ExperienceButton(
                title: "Continue",
                kind: .primary,
                accessibilityIdentifier: "auth.continue"
            ) {
                Task {
                    do {
                        try await authenticationCoordinator.continueAsDevelopmentSessionIfAllowed()
                        ExperienceHaptics.play(.success)
                        statusMessage = nil
                    } catch let authError as AuthenticationError {
                        ExperienceHaptics.play(.warning)
                        statusMessage = UserFacingError.map(authError).message
                    } catch {
                        ExperienceHaptics.play(.warning)
                        statusMessage = UserFacingError.map(AppError.from(.unknown(error.localizedDescription))).message
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            if route == .login {
                ExperienceButton(
                    title: "Onboarding",
                    kind: .secondary,
                    accessibilityIdentifier: "auth.onboarding"
                ) {
                    coordinator.open(.auth(.onboarding))
                }
                .padding(.horizontal, ExperienceSpacing.xl)
            }

            if authenticationManager.state.isAuthenticated {
                ExperienceButton(
                    title: "Sign Out",
                    kind: .destructive,
                    accessibilityIdentifier: "auth.signOut"
                ) {
                    Task {
                        await authenticationCoordinator.logout()
                    }
                }
                .padding(.horizontal, ExperienceSpacing.xl)
            }
        }
        .padding()
        .navigationTitle(authTitle(route))
    }

    private func authTitle(_ route: AuthRoute) -> String {
        switch route {
        case .login: return "Login"
        case .resetPassword: return "Reset Password"
        case .onboarding: return "Onboarding"
        case .choosePlan: return "Choose Plan"
        case .finishTrial: return "Finish Trial"
        }
    }
}
