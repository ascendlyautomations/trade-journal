import Foundation

/// Per-tab typed navigation paths.
///
/// Prefer typed arrays over untyped `NavigationPath` so state restoration
/// and deep links remain deterministic.
struct NavigationPathStore: Codable, Hashable, Sendable {
    var home: [HomeRoute] = []
    var feed: [FeedRoute] = []
    var messages: [MessagesRoute] = []
    var profile: [ProfileRoute] = []
    var auth: [AuthRoute] = []

    mutating func pop(_ tab: TabIdentifier) {
        switch tab {
        case .home:
            if !home.isEmpty { home.removeLast() }
        case .feed:
            if !feed.isEmpty { feed.removeLast() }
        case .messages:
            if !messages.isEmpty { messages.removeLast() }
        case .profile:
            if !profile.isEmpty { profile.removeLast() }
        case .create:
            break
        }
    }

    mutating func popToRoot(_ tab: TabIdentifier) {
        switch tab {
        case .home: home.removeAll()
        case .feed: feed.removeAll()
        case .messages: messages.removeAll()
        case .profile: profile.removeAll()
        case .create: break
        }
    }

    mutating func resetAuth(to route: AuthRoute = .login) {
        // Login is the auth stack root; secondary routes are pushed.
        auth = route == .login ? [] : [route]
    }
}
