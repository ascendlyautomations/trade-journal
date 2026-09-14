import Foundation

/// When the Withdrawals screen is visible, payout ledger/cycle GETs use visible network scheduling.
nonisolated enum WithdrawalsHydrationPriorityGate {
    private static let lock = NSLock()
    private static var screenActive = false

    static func setScreenActive(_ active: Bool) {
        lock.lock()
        screenActive = active
        lock.unlock()
    }

    static var prefersVisibleHydration: Bool {
        lock.lock()
        defer { lock.unlock() }
        return screenActive
    }
}
