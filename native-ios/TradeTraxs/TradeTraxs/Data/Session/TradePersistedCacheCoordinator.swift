import Foundation

/// Patches trade rows in on-disk bootstrap/session caches after a successful journal mutation.
///
/// Cold launch with `dashboard bootstrap path=cache_fresh` re-applies `BackendV2BootstrapDiskCache`
/// into `SessionOwnerTradesStore` and `DetailPresentationCache`, overwriting in-memory + SessionDiskCache
/// seeds unless the dashboard disk blob is updated centrally here.
nonisolated enum TradePersistedCacheCoordinator {
    static func noteUpserted(_ trade: Trade) {
        BackendV2BootstrapDiskCache.patchTrade(trade, viewerID: trade.ownerProfileID.rawValue)
        Task { @MainActor in
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: trade.ownerProfileID)
            let viewerID = trade.ownerProfileID
            ProfilePersistedCacheCoordinator.patchTrade(trade, viewerID: viewerID)
            FeedPersistedCacheCoordinator.patchTrade(trade, viewerID: viewerID)
        }
    }

    static func noteDeleted(id: TradeID, owner: ProfileID) {
        BackendV2BootstrapDiskCache.removeTrade(id: id.rawValue, viewerID: owner.rawValue)
        Task { @MainActor in
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: owner)
            ProfilePersistedCacheCoordinator.removeTrade(id: id, owner: owner, viewerID: owner)
            FeedPersistedCacheCoordinator.removeEntry(viewerID: owner, entryID: id.rawValue)
        }
    }
}
