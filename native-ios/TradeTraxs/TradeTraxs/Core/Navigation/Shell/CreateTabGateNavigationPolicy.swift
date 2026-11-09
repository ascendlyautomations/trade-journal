import Foundation

/// SwiftUI path depth — when non-empty, the tab bar is hidden on pushed surfaces (DM thread, detail, etc.).
enum CreateTabGateNavigationPolicy {
    static func shouldAllowCreateTabShield(
        selectedTab: TabIdentifier,
        paths: NavigationPathStore
    ) -> Bool {
        switch selectedTab {
        case .home:
            return paths.home.isEmpty
        case .feed:
            return paths.feed.isEmpty
        case .messages:
            return paths.messages.isEmpty
        case .profile:
            return paths.profile.isEmpty
        case .create:
            return false
        }
    }
}
