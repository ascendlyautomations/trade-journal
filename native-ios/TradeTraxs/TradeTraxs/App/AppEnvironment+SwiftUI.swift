import SwiftUI

private struct AppEnvironmentKey: EnvironmentKey {
    /// SwiftUI reads `defaultValue` frequently (including during re-renders).
    /// Must be side-effect free after first resolution — never call bootstrap here.
    static var defaultValue: AppEnvironment {
        AppLaunchEnvironment.shared
    }
}

private struct NavigationEnvironmentKey: EnvironmentKey {
    /// Share the same process graph — do not bootstrap a second time.
    static var defaultValue: NavigationEnvironment {
        AppLaunchEnvironment.shared.navigation
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
