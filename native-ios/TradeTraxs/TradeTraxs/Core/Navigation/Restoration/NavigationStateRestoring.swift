import Foundation

/// Persists and restores ``NavigationState`` across launches / scenes.
protocol NavigationStateRestoring: Sendable {
    func load() -> NavigationState?
    func save(_ state: NavigationState)
    func clear()
}

/// UserDefaults-backed restoration (no Keychain; routes are non-secret).
struct UserDefaultsNavigationStateRestorer: NavigationStateRestoring {
    private let key: String
    private let defaults: UserDefaults

    init(key: String = "tt.navigation.state.v1", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> NavigationState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NavigationState.self, from: data)
    }

    func save(_ state: NavigationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// Applies restoration policy when bootstrapping navigation.
enum NavigationRestorationPolicy {
    /// Cold start: prefer restored authenticated state; always safe-fallback.
    static func bootstrapState(
        restorer: any NavigationStateRestoring,
        preferRestoredSession: Bool = true
    ) -> NavigationState {
        guard preferRestoredSession, let restored = restorer.load() else {
            return .initial
        }
        // Never restore into Create tab.
        var state = restored
        if state.selectedTab == .create {
            state.selectedTab = state.previousContentTab
        }
        // Do not restore ephemeral presentations.
        state.presentedSheet = nil
        state.presentedFullScreen = nil
        return state
    }
}
