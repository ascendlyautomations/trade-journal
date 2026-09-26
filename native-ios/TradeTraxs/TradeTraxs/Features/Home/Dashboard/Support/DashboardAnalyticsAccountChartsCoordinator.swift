import Foundation

/// Account chart fetch coalescing + selection-scoped apply (no stale account overwrite).
@MainActor
enum DashboardAnalyticsAccountChartsCoordinator {
    private static var selectionToken: UInt64 = 0
    private static var inFlightAccountID: TradingAccountID?

    /// Call when the user changes account filter — invalidates pending apply for prior selection.
    static func bumpSelection() -> UInt64 {
        selectionToken &+= 1
        inFlightAccountID = nil
        return selectionToken
    }

    static func currentSelectionToken() -> UInt64 {
        selectionToken
    }

    static func loadIfNeeded(
        selectedAccountID: TradingAccountID,
        selectionToken token: UInt64,
        revision: Int64,
        viewerID: ProfileID,
        rpc: any RPCClient
    ) async -> Bool {
        let store = DashboardAnalyticsAccountChartsStore.shared
        if let cached = store.charts(accountID: selectedAccountID, revision: revision),
           store.availability(accountID: selectedAccountID, revision: revision).isLoaded,
           DashboardAnalyticsChartsSupport.hasEquityPoints(cached),
           !DashboardAnalyticsChartsSupport.hasVisualExpansionContract(cached)
        {
            #if DEBUG
            DashboardVisualExpansionDebug.logStaleChartsCache(
                scope: "account:\(selectedAccountID.rawValue)",
                revision: revision
            )
            #endif
            store.dropCharts(accountID: selectedAccountID, revision: revision)
        }
        if store.availability(accountID: selectedAccountID, revision: revision).isLoaded,
           let cached = store.charts(accountID: selectedAccountID, revision: revision),
           DashboardAnalyticsChartsSupport.chartsReadyForPresentation(cached)
        {
            return token == selectionToken
        }

        store.markLoading(accountID: selectedAccountID, revision: revision)
        inFlightAccountID = selectedAccountID

        do {
            _ = try await DashboardAnalyticsAccountChartsLoader.loadCoalesced(
                accountID: selectedAccountID,
                revision: revision,
                rpc: rpc,
                viewerID: viewerID
            )
        } catch {
            if token == selectionToken, inFlightAccountID == selectedAccountID {
                store.markFailed(accountID: selectedAccountID, revision: revision)
            }
            return false
        }

        guard token == selectionToken else { return false }
        guard inFlightAccountID == selectedAccountID else { return false }
        return store.availability(accountID: selectedAccountID, revision: revision).isLoaded
    }
}
