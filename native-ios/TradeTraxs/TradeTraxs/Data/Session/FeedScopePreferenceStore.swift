import Foundation

/// Per-user Feed scope preference saved when the viewer manually switches tabs (current session UX).
nonisolated enum FeedScopePreferenceStore {
    private static let prefix = "feed.scope.preference."

    static func savedScope(for userID: UserID) -> FeedScope? {
        guard let raw = UserDefaults.standard.string(forKey: key(for: userID)),
              let scope = FeedScope(rawValue: raw)
        else {
            return nil
        }
        return scope
    }

    static func save(_ scope: FeedScope, for userID: UserID) {
        UserDefaults.standard.set(scope.rawValue, forKey: key(for: userID))
    }

    private static func key(for userID: UserID) -> String {
        "\(prefix)\(userID.rawValue)"
    }
}
