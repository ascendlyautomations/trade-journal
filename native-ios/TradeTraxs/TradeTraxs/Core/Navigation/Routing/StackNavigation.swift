import SwiftUI

/// Stack-scoped navigation actions for views rendered inside a tab `NavigationStack`.
///
/// Shared destinations (Settings, etc.) append to the path of the stack that is
/// currently rendering them — never a global tab guess or host-tab variable.
@MainActor
struct StackNavigation {
    private let appendSettingsRoute: (SettingsRoute) -> Void

    init(appendSettingsRoute: @escaping (SettingsRoute) -> Void) {
        self.appendSettingsRoute = appendSettingsRoute
    }

    /// Append one Settings destination to the active stack path.
    func pushSettings(_ route: SettingsRoute) {
        appendSettingsRoute(route)
    }

    static func home(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            store.paths.home.append(.settings(route))
        }
    }

    static func feed(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            store.paths.feed.append(.settings(route))
        }
    }

    static func messages(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            store.paths.messages.append(.settings(route))
        }
    }

    static func profile(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            store.paths.profile.append(.settings(route))
        }
    }
}

private struct StackNavigationKey: EnvironmentKey {
    static let defaultValue: StackNavigation? = nil
}

extension EnvironmentValues {
    var stackNavigation: StackNavigation? {
        get { self[StackNavigationKey.self] }
        set { self[StackNavigationKey.self] = newValue }
    }
}
