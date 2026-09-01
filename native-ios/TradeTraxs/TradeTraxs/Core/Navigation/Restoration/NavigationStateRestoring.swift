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

    init(key: String = "tt.navigation.state.v2", defaults: UserDefaults = .standard) {
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
    struct BootstrapResult: Sendable {
        var shellState: NavigationState
        var deferredAuthenticatedPaths: NavigationState?
    }

    /// Cold start: load tab preference only — paths restore after auth succeeds.
    static func bootstrapState(
        restorer: any NavigationStateRestoring,
        preferRestoredSession: Bool = true
    ) -> BootstrapResult {
        guard preferRestoredSession, let restored = restorer.load() else {
            return BootstrapResult(shellState: .initial, deferredAuthenticatedPaths: nil)
        }
        var shell = restored
        if shell.selectedTab == .create {
            shell.selectedTab = shell.previousContentTab
        }
        shell.presentedSheet = nil
        shell.presentedFullScreen = nil
        shell.sessionPhase = .unauthenticated

        shell.homePath = []
        shell.feedPath = []
        shell.messagesPath = []
        shell.profilePath = []
        return BootstrapResult(shellState: shell, deferredAuthenticatedPaths: restored)
    }
}
