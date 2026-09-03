import Foundation

/// Per-trading-day guardrail dismissals — avoids spamming the same notice.
@MainActor
final class PsychologyGuardrailDismissStore {
    static let shared = PsychologyGuardrailDismissStore()

    private var dismissedKeys: Set<String> = []

    private init() {}

    func isDismissed(_ key: String) -> Bool {
        dismissedKeys.contains(key)
    }

    func dismiss(_ key: String) {
        dismissedKeys.insert(key)
    }

    func dismissedKeysForToday(tradingDay: String) -> [String] {
        dismissedKeys.filter { $0.hasSuffix(".\(tradingDay)") }
    }

    func resetSession() {
        dismissedKeys.removeAll()
    }
}
