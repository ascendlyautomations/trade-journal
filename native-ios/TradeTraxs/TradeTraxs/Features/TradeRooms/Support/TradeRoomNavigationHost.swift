import Foundation

/// Keeps Trade Room pushes on the tab stack that opened the room.
enum TradeRoomNavigationHost: Hashable, Sendable {
    case messages
    case feed
    case profile

    func room(_ id: RoomID) -> AppDestination {
        switch self {
        case .messages: return .messages(.room(id))
        case .feed: return .feed(.room(id))
        case .profile: return .profile(.room(id))
        }
    }

    func members(_ id: RoomID) -> AppDestination {
        switch self {
        case .messages: return .messages(.roomMembers(id))
        case .feed: return .feed(.roomMembers(id))
        case .profile: return .profile(.roomMembers(id))
        }
    }

    func info(_ id: RoomID) -> AppDestination {
        switch self {
        case .messages: return .messages(.roomInfo(id))
        case .feed: return .feed(.roomInfo(id))
        case .profile: return .profile(.roomInfo(id))
        }
    }

    func profile(_ id: ProfileID) -> AppDestination {
        switch self {
        case .messages: return .messages(.profile(id))
        case .feed: return .feed(.profile(id))
        case .profile: return .profile(.otherProfile(id))
        }
    }
}
