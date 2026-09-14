import Foundation

/// Patches owner account rows in on-disk bootstrap/session caches after a successful account mutation.
nonisolated enum AccountPersistedCacheCoordinator {
    static func noteAccountsUpdated(_ accounts: [TradingAccount], viewerID: ProfileID) {
        BackendV2BootstrapDiskCache.replaceAccounts(accounts, viewerID: viewerID.rawValue)
        Task { @MainActor in
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: viewerID)
        }
    }

    static func noteAccountPatched(_ account: TradingAccount, viewerID: ProfileID) {
        BackendV2BootstrapDiskCache.patchAccount(account, viewerID: viewerID.rawValue)
        Task { @MainActor in
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: viewerID)
        }
    }
}
