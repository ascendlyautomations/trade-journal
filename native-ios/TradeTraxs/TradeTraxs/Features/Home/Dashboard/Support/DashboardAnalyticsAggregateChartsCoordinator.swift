import Foundation

/// All-accounts chart fetch coalescing + selection-scoped apply.
@MainActor
enum DashboardAnalyticsAggregateChartsCoordinator {
    private static var selectionToken: UInt64 = 0
    private static var inFlight = false

    static func bumpSelection() -> UInt64 {
        selectionToken &+= 1
        inFlight = false
        return selectionToken
    }

    static func loadIfNeeded(
        selectionToken token: UInt64,
        revision: Int64,
        viewerID: ProfileID,
        rpc: any RPCClient
    ) async -> Bool {
        let store = DashboardAnalyticsAggregateChartsStore.shared
        if store.availability(revision: revision).isLoaded,
           let cached = store.charts(revision: revision),
           DashboardAnalyticsChartsSupport.hasEquityPoints(cached)
        {
            return token == selectionToken
        }

        store.markLoading(revision: revision)
        inFlight = true

        do {
            _ = try await DashboardAnalyticsAggregateChartsLoader.loadCoalesced(
                revision: revision,
                rpc: rpc,
                viewerID: viewerID
            )
        } catch {
            if token == selectionToken, inFlight {
                store.markFailed(revision: revision)
            }
            return false
        }

        guard token == selectionToken else { return false }
        guard inFlight else { return false }
        return store.availability(revision: revision).isLoaded
    }
}
