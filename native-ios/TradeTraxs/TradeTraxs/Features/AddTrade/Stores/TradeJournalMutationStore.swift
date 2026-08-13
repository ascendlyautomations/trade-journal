import Foundation
import Observation

/// Broadcasts journal mutations so Dashboard / Calendar / Profile can refresh without polling.
@Observable
@MainActor
final class TradeJournalMutationStore {
    static let shared = TradeJournalMutationStore()

    private(set) var revision: Int = 0
    private(set) var latestCreatedTrade: Trade?

    private init() {}

    func noteCreated(_ trade: Trade) {
        latestCreatedTrade = trade
        // Targeted session cache updates — screens observe revision for incremental patch.
        TradeHistorySessionStore.shared.noteCreated(trade)
        CalendarMonthSessionStore.shared.noteCreated(trade)
        SessionNetworkProbe.record(.localMutation, resource: "journal.trade", detail: trade.id.rawValue)
        revision += 1
    }

    /// CSV / bulk import — lists need revalidation (many rows).
    func noteBulkImport() {
        latestCreatedTrade = nil
        TradeHistorySessionStore.shared.invalidateLists()
        CalendarMonthSessionStore.shared.invalidate()
        SessionNetworkProbe.record(.cacheInvalidated, resource: "journal.bulkImport")
        revision += 1
    }

    func invalidate() {
        latestCreatedTrade = nil
        revision = 0
    }
}
