import Foundation

/// Which tab stack owns the Activity screen (Dashboard vs Profile entry).
enum ActivityNavigationHost: Hashable, Sendable {
    case home
    case profile
}
