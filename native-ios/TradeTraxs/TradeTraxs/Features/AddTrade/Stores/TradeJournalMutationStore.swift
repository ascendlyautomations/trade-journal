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
    private weak var vaultStore: VaultStore?

    private init() {}

    /// Bind the shared presentation cache once at app bootstrap — central upsert path for all journal mutations.
    func configure(detailCache: DetailPresentationCache, vaultStore: VaultStore? = nil) {
        self.detailCache = detailCache
        self.vaultStore = vaultStore
    }

    func noteCreated(_ trade: Trade) {
        latest = .created(trade)
        propagateUpsert(trade, resource: "journal.trade.created")
        revision += 1
        AnalyticsLocalMutationRouter.submit(
            kind: .create,
            scope: AnalyticsLocalMutationScopeBuilder.create(trade: trade)
        )
        ProfileAnalyticsOwnerInvalidation.submitTradeMutation(old: nil, new: trade)
        GettingStartedRefreshCenter.noteTradePersisted(trade)
    }

    func noteUpdated(_ trade: Trade, previous: Trade? = nil) {
        latest = .updated(trade)
        propagateUpsert(trade, resource: "journal.trade.updated")
        revision += 1
        let scope: AnalyticalMutationScope
        if let previous {
            scope = AnalyticsLocalMutationScopeBuilder.update(old: previous, new: trade)
        } else {
            scope = AnalyticsLocalMutationScopeBuilder.create(trade: trade)
        }
        AnalyticsLocalMutationRouter.submit(kind: .update, scope: scope)
        ProfileAnalyticsOwnerInvalidation.submitTradeMutation(old: previous, new: trade)
        GettingStartedRefreshCenter.noteTradeVisibilityUpdated(trade, previous: previous)
    }

    private func propagateUpsert(_ trade: Trade, resource: String) {
        if let detailCache {
            detailCache.seedAuthoritativeDetail(trade, authority: .authoritativeMutation)
            SessionOwnerTradesStore.shared.upsert(trade, detailCache: detailCache)
            SessionTradeEntityStore.shared.upsert(trade, detailCache: detailCache, viewerID: trade.ownerProfileID)
        }
        TradeHistorySessionStore.shared.noteUpserted(trade)
        CalendarMonthSessionStore.shared.noteUpserted(trade)
        TradePersistedCacheCoordinator.noteUpserted(trade)
        SessionNetworkProbe.record(.localMutation, resource: resource, detail: trade.id.rawValue)
    }

    func noteDeleted(id: TradeID, owner: ProfileID, previous: Trade? = nil) {
        latest = .deleted(id: id, owner: owner)
        detailCache?.removeTrade(id: id)
        SessionOwnerTradesStore.shared.remove(id: id, owner: owner)
        SessionTradeEntityStore.shared.remove(id: id)
        TradeHistorySessionStore.shared.noteDeleted(id: id, owner: owner)
        CalendarMonthSessionStore.shared.noteDeleted(id: id)
        TradePersistedCacheCoordinator.noteDeleted(id: id, owner: owner)
        vaultStore?.pruneContentReference(
            VaultContentRef(contentType: .trade, contentID: id.rawValue)
        )
        Task {
            await VaultPersistedCacheCoordinator.shared.persistVaultPresentation(
                reason: "tradeDeleted",
                isRollback: false
            )
        }
        SessionNetworkProbe.record(.localMutation, resource: "journal.trade.deleted", detail: id.rawValue)
        revision += 1
        if let previous {
            AnalyticsLocalMutationRouter.submit(
                kind: .delete,
                scope: AnalyticsLocalMutationScopeBuilder.delete(old: previous)
            )
            ProfileAnalyticsOwnerInvalidation.submitTradeMutation(old: previous, new: nil)
        }
    }

    /// CSV / bulk import — bounded invalidation; authoritative reload via mounted observers.
    func noteBulkImport(
        owner: ProfileID,
        source: AnalyticsBulkImportSource = .unknown,
        persistedTradeCount: Int = 0
    ) {
        latest = .bulkImport
        detailCache?.invalidateJournalLists()
        SessionOwnerTradesStore.shared.invalidate(profileID: owner)
        SessionTradeEntityStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidateLists()
        CalendarMonthSessionStore.shared.invalidate()
        ViewerSyncStateRuntime.noteLocalMutation(viewerID: owner)
        SessionNetworkProbe.record(.cacheInvalidated, resource: "journal.bulkImport")
        revision += 1
        Task { @MainActor in
            let visible = AnalyticsLocalMutationRouter.visibleMonthBoundsForBulk()
            let scope = AnalyticsLocalMutationScopeBuilder.bulkImport(
                viewerID: owner,
                visibleMonth: visible
            )
            AnalyticsLocalMutationRouter.submit(kind: .bulk, scope: scope, bulkSource: source)
        }
        GettingStartedRefreshCenter.noteTradesBulkPersisted(count: persistedTradeCount)
    }

    func invalidate() {
        latest = nil
        revision = 0
    }
}
