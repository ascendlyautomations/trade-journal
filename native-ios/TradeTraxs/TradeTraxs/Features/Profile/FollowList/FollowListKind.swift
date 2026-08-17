import Foundation

enum FollowListKind: String, Hashable, Sendable {
    case followers
    case following

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }

    var emptyTitle: String {
        switch self {
        case .followers: return "No followers yet"
        case .following: return "Not following anyone yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .followers: return "When people follow this account, they’ll show up here."
        case .following: return "Find traders on Explore and tap Follow to start building your list."
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .followers: return "Search followers"
        case .following: return "Search following"
        }
    }
}
