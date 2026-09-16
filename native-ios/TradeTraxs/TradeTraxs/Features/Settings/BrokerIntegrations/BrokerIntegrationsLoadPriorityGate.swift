import Foundation

/// When Broker Integrations (or broker onboarding) is visible, primary connection list BFF GETs use visible scheduling.
nonisolated enum BrokerIntegrationsLoadPriorityGate {
    private static let lock = NSLock()
    private static var screenActive = false

    static func setScreenActive(_ active: Bool) {
        lock.lock()
        screenActive = active
        lock.unlock()
    }

    static var prefersVisibleBrokerConnectionLoad: Bool {
        lock.lock()
        defer { lock.unlock() }
        return screenActive
    }
}
