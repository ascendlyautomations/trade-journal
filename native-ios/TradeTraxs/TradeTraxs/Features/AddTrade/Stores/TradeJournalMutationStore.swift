import Foundation
import Observation

/// Broadcasts journal mutations so Dashboard / Calendar / Profile can refresh without polling.
@Observable
@MainActor
final class TradeJournalMutationStore {
    static let shared = TradeJournalMutationStore()

    enum Kind: Equatable {
        case created(Trade)
        case updated(Trade)
        case deleted(id: TradeID, owner: ProfileID)
        case bulkImport
    }

    private(set) var revision: Int = 0
    private(set) var latest: Kind?

    /// Back-compat for create-only observers (Feed / Profile public insert).
    var latestCreatedTrade: Trade? {
        if case .created(let trade) = latest { return trade }
        return nil
    }

    /// Create or update — screens that upsert by ID.
    var latestUpsertedTrade: Trade? {
        switch latest {
        case .created(let trade), .updated(let trade):
            return trade
        case .deleted, .bulkImport, .none:
            return nil
        }
    }

    private init() {}

    func noteCreated(_ trade: Trade) {
        latest = .created(trade)
        // Targeted session cache updates — screens observe revision for incremental patch.
        TradeHistorySessionStore.shared.noteUpserted(trade)
        CalendarMonthSessionStore.shared.noteUpserted(trade)
        SessionNetworkProbe.record(.localMutation, resource: "journal.trade.created", detail: trade.id.rawValue)
        revision += 1
    }

    func noteUpdated(_ trade: Trade) {
        latest = .updated(trade)
        TradeHistorySessionStore.shared.noteUpserted(trade)
        CalendarMonthSessionStore.shared.noteUpserted(trade)
        SessionNetworkProbe.record(.localMutation, resource: "journal.trade.updated", detail: trade.id.rawValue)
        revision += 1
    }

    func noteDeleted(id: TradeID, owner: ProfileID) {
        latest = .deleted(id: id, owner: owner)
        SessionOwnerTradesStore.shared.remove(id: id, owner: owner)
        TradeHistorySessionStore.shared.noteDeleted(id: id, owner: owner)
        CalendarMonthSessionStore.shared.noteDeleted(id: id)
        SessionNetworkProbe.record(.localMutation, resource: "journal.trade.deleted", detail: id.rawValue)
        revision += 1
    }

    /// CSV / bulk import — lists need revalidation (many rows).
    func noteBulkImport() {
        latest = .bulkImport
        TradeHistorySessionStore.shared.invalidateLists()
        CalendarMonthSessionStore.shared.invalidate()
        SessionNetworkProbe.record(.cacheInvalidated, resource: "journal.bulkImport")
        revision += 1
    }

    func invalidate() {
        latest = nil
        revision = 0
    }
}
