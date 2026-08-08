import SwiftUI

private struct AppEnvironmentKey: EnvironmentKey {
    /// Preview / fallback only. Production sets the value from ``TradeTraxsApp``.
    ///
    /// Use `static var` (not `let`) so bootstrap is not forced through a
    /// mismatched actor-isolated constant during EnvironmentKey type-checking.
    static var defaultValue: AppEnvironment {
        CompositionRoot.bootstrap()
    }
}

private struct NavigationEnvironmentKey: EnvironmentKey {
    static var defaultValue: NavigationEnvironment {
        CompositionRoot.bootstrap().navigation
    }
}

extension EnvironmentValues {
    /// Narrow SwiftUI surface for app-wide environment.
    /// Prefer initializer injection for ViewModels and services.
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }

    /// Navigation subgraph (store + coordinator + routers).
    var navigationEnvironment: NavigationEnvironment {
        get { self[NavigationEnvironmentKey.self] }
        set { self[NavigationEnvironmentKey.self] = newValue }
    }
}
