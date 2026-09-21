import Foundation

/// Coordinates post-authentication startup networking into critical visible work vs deferred hydration.
@MainActor
enum AuthenticatedLaunchPhasing {
    private(set) static var criticalVisibleSurfaceReady = false
    private(set) static var activeTab: TabIdentifier = .home

    private static var deferredWaiters: [CheckedContinuation<Void, Never>] = []

    static func reset() {
        criticalVisibleSurfaceReady = false
        activeTab = .home
        resumeDeferredWaiters()
    }

    static func noteActiveTab(_ tab: TabIdentifier) {
        activeTab = tab
    }

    /// Phase B — cached first paint for the active tab (Home Dashboard or Feed).
    static func markCriticalVisibleSurfaceReady(tab: TabIdentifier) {
        guard !criticalVisibleSurfaceReady else { return }
        criticalVisibleSurfaceReady = true
        activeTab = tab
        resumeDeferredWaiters()
    }

    static var allowsDeferredStartupNetworking: Bool {
        criticalVisibleSurfaceReady
    }

    static func waitUntilDeferredStartupNetworkingAllowed() async {
        if criticalVisibleSurfaceReady { return }
        await withCheckedContinuation { continuation in
            deferredWaiters.append(continuation)
        }
    }

    private static func resumeDeferredWaiters() {
        let pending = deferredWaiters
        deferredWaiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
