import Foundation

/// Home tab visibility — defers dashboard authoritative network work while another tab is active.
@MainActor
enum DashboardHomeSurfaceGate {
    static var isHomeTabActive = true

    struct DeferredViewModelRefresh: Sendable {
        var generation: UInt64
        var forceNetwork: Bool
        var isAuthoritativeFollowUp: Bool
        var refreshTrigger: DashboardAuthoritativeRefreshTrigger?
    }

    struct DeferredCoordinatorRefresh: Sendable {
        var viewerID: ProfileID
        var trigger: DashboardAuthoritativeRefreshTrigger
        var loadGeneration: UInt64
    }

    private static var deferredViewModelRefresh: DeferredViewModelRefresh?
    private static var deferredCoordinatorRefresh: DeferredCoordinatorRefresh?

    static func setHomeTabActive(_ active: Bool) {
        isHomeTabActive = active
        ActiveScreenBootstrapPriorityGate.home.setScreenActive(active)
    }

    static func enqueueViewModelRefresh(_ request: DeferredViewModelRefresh) {
        deferredViewModelRefresh = coalesceViewModel(deferredViewModelRefresh, request)
    }

    static func enqueueCoordinatorRefresh(_ request: DeferredCoordinatorRefresh) {
        deferredCoordinatorRefresh = coalesceCoordinator(deferredCoordinatorRefresh, request)
    }

    static func takeDeferredViewModelRefresh() -> DeferredViewModelRefresh? {
        let pending = deferredViewModelRefresh
        deferredViewModelRefresh = nil
        return pending
    }

    static func takeDeferredCoordinatorRefresh() -> DeferredCoordinatorRefresh? {
        let pending = deferredCoordinatorRefresh
        deferredCoordinatorRefresh = nil
        return pending
    }

    static func resetForSessionBoundary() {
        isHomeTabActive = true
        deferredViewModelRefresh = nil
        deferredCoordinatorRefresh = nil
        ActiveScreenBootstrapPriorityGate.home.setScreenActive(true)
    }

    #if DEBUG
    static func resetForTesting() {
        resetForSessionBoundary()
    }
    #endif

    private static func coalesceViewModel(
        _ existing: DeferredViewModelRefresh?,
        _ incoming: DeferredViewModelRefresh
    ) -> DeferredViewModelRefresh {
        guard let existing else { return incoming }
        let trigger = strongerTrigger(existing.refreshTrigger, incoming.refreshTrigger)
        return DeferredViewModelRefresh(
            generation: max(existing.generation, incoming.generation),
            forceNetwork: existing.forceNetwork || incoming.forceNetwork,
            isAuthoritativeFollowUp: existing.isAuthoritativeFollowUp || incoming.isAuthoritativeFollowUp,
            refreshTrigger: trigger
        )
    }

    private static func coalesceCoordinator(
        _ existing: DeferredCoordinatorRefresh?,
        _ incoming: DeferredCoordinatorRefresh
    ) -> DeferredCoordinatorRefresh {
        guard let existing else { return incoming }
        return DeferredCoordinatorRefresh(
            viewerID: incoming.viewerID,
            trigger: strongerTrigger(existing.trigger, incoming.trigger),
            loadGeneration: max(existing.loadGeneration, incoming.loadGeneration)
        )
    }

    private static func strongerTrigger(
        _ a: DashboardAuthoritativeRefreshTrigger?,
        _ b: DashboardAuthoritativeRefreshTrigger?
    ) -> DashboardAuthoritativeRefreshTrigger? {
        guard let a else { return b }
        guard let b else { return a }
        return triggerRank(a) >= triggerRank(b) ? a : b
    }

    private static func triggerRank(_ trigger: DashboardAuthoritativeRefreshTrigger) -> Int {
        switch trigger {
        case .journalMutation: return 50
        case .pullRefresh: return 40
        case .staleAuthoritative: return 30
        case .viewerSync: return 25
        case .displayOnlyRevalidate: return 20
        case .cold: return 10
        }
    }

    private static func strongerTrigger(
        _ a: DashboardAuthoritativeRefreshTrigger,
        _ b: DashboardAuthoritativeRefreshTrigger
    ) -> DashboardAuthoritativeRefreshTrigger {
        triggerRank(a) >= triggerRank(b) ? a : b
    }
}
