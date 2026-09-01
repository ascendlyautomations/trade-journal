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

    private var detailCache: DetailPresentationCache?

    private init() {}

    /// Bind the shared presentation cache once at app bootstrap — central upsert path for all journal mutations.
    func configure(detailCache: DetailPresentationCache) {
        self.detailCache = detailCache
    }

    func noteCreated(_ trade: Trade) {
        latest = .created(trade)
        propagateUpsert(trade, resource: "journal.trade.created")
        revision += 1
    }

    func noteUpdated(_ trade: Trade) {
        latest = .updated(trade)
        propagateUpsert(trade, resource: "journal.trade.updated")
        revision += 1
    }

    private func propagateUpsert(_ trade: Trade, resource: String) {
        if let detailCache {
            detailCache.seed(trade)
            SessionOwnerTradesStore.shared.upsert(trade, detailCache: detailCache)
            SessionTradeEntityStore.shared.upsert(trade, detailCache: detailCache)
        }
        TradeHistorySessionStore.shared.noteUpserted(trade)
        CalendarMonthSessionStore.shared.noteUpserted(trade)
        TradePersistedCacheCoordinator.noteUpserted(trade)
        SessionNetworkProbe.record(.localMutation, resource: resource, detail: trade.id.rawValue)
    }

    func noteDeleted(id: TradeID, owner: ProfileID) {
        latest = .deleted(id: id, owner: owner)
        SessionOwnerTradesStore.shared.remove(id: id, owner: owner)
        TradeHistorySessionStore.shared.noteDeleted(id: id, owner: owner)
        CalendarMonthSessionStore.shared.noteDeleted(id: id)
        TradePersistedCacheCoordinator.noteDeleted(id: id, owner: owner)
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
