import Foundation

/// Constructed graph of application services.
///
/// Built only by ``CompositionRoot``. Consumers receive dependencies through
/// initializers (or a narrow SwiftUI `Environment` surface) — never by looking
/// services up from a global locator.
struct DependencyContainer {
    /// Placeholder slot for future platform services.
    let placeholders: PlaceholderServices

    /// Production navigation subgraph.
    let navigation: NavigationEnvironment

    /// Production networking subgraph.
    let networking: NetworkingEnvironment

    /// Production data subgraph (repositories, cache, realtime seams).
    let data: DataEnvironment

    /// Production authentication subgraph.
    let authentication: AuthenticationEnvironment

    static func make(
        configuration: AppConfiguration,
        navigation: NavigationEnvironment,
        networking: NetworkingEnvironment,
        data: DataEnvironment,
        authentication: AuthenticationEnvironment
    ) -> DependencyContainer {
        DependencyContainer(
            placeholders: PlaceholderServices(configuration: configuration),
            navigation: navigation,
            networking: networking,
            data: data,
            authentication: authentication
        )
    }
}

/// Intentionally empty service bag for non-navigation services.
struct PlaceholderServices: Sendable {
    let configuration: AppConfiguration
}
