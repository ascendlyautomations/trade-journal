import Foundation

/// Hooks for UIScene / NSUserActivity style restoration.
///
/// Phase 3A provides the interface and Codable state bridging.
/// Wire `UISceneSession` state in AppDelegate / scene delegate when needed.
protocol SceneRestoring: Sendable {
    func encodeNavigationState(_ state: NavigationState) -> Data?
    func decodeNavigationState(from data: Data) -> NavigationState?
    func userActivity(for state: NavigationState) -> NSUserActivity
}

struct SceneRestorationBridge: SceneRestoring {
    static let activityType = "com.tradetraxs.ios.navigation"

    func encodeNavigationState(_ state: NavigationState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    func decodeNavigationState(from data: Data) -> NavigationState? {
        try? JSONDecoder().decode(NavigationState.self, from: data)
    }

    func userActivity(for state: NavigationState) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.title = "TradeTraxs"
        activity.userInfo = [
            "selectedTab": state.selectedTab.rawValue,
            "sessionPhase": state.sessionPhase.rawValue,
        ]
        if let data = encodeNavigationState(state) {
            activity.userInfo?["navigationState"] = data
        }
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = false
        return activity
    }
}
