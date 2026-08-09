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
    let allowsDevelopmentBypass: Bool

    var body: some View {
        NavigationStack(path: authPath) {
            AuthRouteView(
                route: .login,
                navigationCoordinator: coordinator,
                authenticationCoordinator: authenticationCoordinator,
                allowsDevelopmentBypass: allowsDevelopmentBypass
            )
            .navigationDestination(for: AuthRoute.self) { route in
                AuthRouteView(
                    route: route,
                    navigationCoordinator: coordinator,
                    authenticationCoordinator: authenticationCoordinator,
                    allowsDevelopmentBypass: allowsDevelopmentBypass
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
