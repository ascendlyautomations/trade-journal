import Foundation

/// Patches trade rows in on-disk bootstrap/session caches after a successful journal mutation.
///
/// Cold launch with `dashboard bootstrap path=cache_fresh` re-applies `BackendV2BootstrapDiskCache`
/// into `SessionOwnerTradesStore` and `DetailPresentationCache`, overwriting in-memory + SessionDiskCache
/// seeds unless the dashboard disk blob is updated centrally here.
nonisolated enum TradePersistedCacheCoordinator {
    static func noteUpserted(_ trade: Trade) {
        BackendV2BootstrapDiskCache.patchTrade(trade, viewerID: trade.ownerProfileID.rawValue)
    }

    static func noteDeleted(id: TradeID, owner: ProfileID) {
        BackendV2BootstrapDiskCache.removeTrade(id: id.rawValue, viewerID: owner.rawValue)
    }
}
