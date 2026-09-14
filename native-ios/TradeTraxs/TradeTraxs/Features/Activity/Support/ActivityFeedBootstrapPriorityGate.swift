import Foundation

/// When the Activity screen is visible, its feed bootstrap RPC should use visible scheduling.
nonisolated enum ActivityFeedBootstrapPriorityGate {
    private static let lock = NSLock()
    private static var screenActive = false

    static func setScreenActive(_ active: Bool) {
        lock.lock()
        screenActive = active
        lock.unlock()
    }

    static var prefersVisibleBootstrap: Bool {
        lock.lock()
        defer { lock.unlock() }
        return screenActive
    }
}
