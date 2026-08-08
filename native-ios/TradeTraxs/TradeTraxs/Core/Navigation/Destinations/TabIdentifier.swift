import Foundation

/// Permanent bottom-tab modes. Create is an action tab (not a content stack).
enum TabIdentifier: String, CaseIterable, Codable, Hashable, Sendable {
    case home
    case feed
    case create
    case messages
    case profile

    /// Tabs that own a retained `NavigationStack`.
    var storesNavigationStack: Bool {
        switch self {
        case .home, .feed, .messages, .profile:
            return true
        case .create:
            return false
        }
    }

    /// Content tabs users return to after Create.
    var isContentTab: Bool { storesNavigationStack }

    var displayName: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        case .create: return "Create"
        case .messages: return "Messages"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "rectangle.stack.fill"
        case .create: return "plus.circle.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    static var defaultContentTab: TabIdentifier { .home }
}
