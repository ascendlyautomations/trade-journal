import Foundation

/// One-time plan chooser completion — not cleared on logout (per account).
struct PostOnboardingPlanSelectionProgressStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func storageKey(userID: String) -> String {
        "tt.postOnboarding.planSelection.completed.\(userID)"
    }

    func hasCompleted(userID: String) -> Bool {
        defaults.bool(forKey: Self.storageKey(userID: userID))
    }

    func markCompleted(userID: String) {
        defaults.set(true, forKey: Self.storageKey(userID: userID))
    }

    func clear(userID: String) {
        defaults.removeObject(forKey: Self.storageKey(userID: userID))
    }
}