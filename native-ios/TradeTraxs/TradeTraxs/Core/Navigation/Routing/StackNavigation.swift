import SwiftUI
import OSLog

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
            appendSettingsRoute(route, to: &store.paths.home, stack: "home") { .settings($0) }
        }
    }

    static func feed(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            appendSettingsRoute(route, to: &store.paths.feed, stack: "feed") { .settings($0) }
        }
    }

    static func messages(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            appendSettingsRoute(route, to: &store.paths.messages, stack: "messages") { .settings($0) }
        }
    }

    static func profile(store: NavigationStore) -> StackNavigation {
        StackNavigation { route in
            appendSettingsRoute(route, to: &store.paths.profile, stack: "profile") { .settings($0) }
        }
    }

    private static func appendSettingsRoute<Route: Hashable>(
        _ settingsRoute: SettingsRoute,
        to path: inout [Route],
        stack: String,
        make: (SettingsRoute) -> Route
    ) {
        let next = make(settingsRoute)
        if path.last == next {
            logSettingsPush(settingsRoute: settingsRoute, stack: stack, skippedDuplicate: true, depth: path.count)
            return
        }
        if settingsRoute == .home {
            let home = make(.home)
            if let existingIndex = path.lastIndex(of: home) {
                path = Array(path.prefix(existingIndex + 1))
                logSettingsPush(
                    settingsRoute: settingsRoute,
                    stack: stack,
                    skippedDuplicate: true,
                    depth: path.count
                )
                return
            }
        }
        path.append(next)
        logSettingsPush(settingsRoute: settingsRoute, stack: stack, skippedDuplicate: false, depth: path.count)
    }

    private static func logSettingsPush(
        settingsRoute: SettingsRoute,
        stack: String,
        skippedDuplicate: Bool,
        depth: Int
    ) {
        #if DEBUG
        AppLog.navigation.debug(
            """
            settings.stack.push route=\(settingsRoute.rawValue, privacy: .public) \
            stack=\(stack, privacy: .public) \
            duplicateSkip=\(skippedDuplicate, privacy: .public) \
            depth=\(depth, privacy: .public)
            """
        )
        #endif
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
