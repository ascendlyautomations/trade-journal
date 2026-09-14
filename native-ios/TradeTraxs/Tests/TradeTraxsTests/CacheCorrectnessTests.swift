import XCTest
@testable import TradeTraxs

@MainActor
final class CacheCorrectnessTests: XCTestCase {
    private let viewerID = ProfileID("11111111-1111-1111-1111-111111111111")

    override func tearDown() {
        BackendV2BootstrapDiskCache.clearAll()
        SessionOwnerTradesStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        super.tearDown()
    }

    func testTradeDeleteRemovesDetailCacheCentrally() {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        let trade = ProfileTradeFixtures.samples(owner: viewerID)[0]
        cache.seed(trade)
        cache.seed(publicTrades: [trade], for: viewerID)

        TradeJournalMutationStore.shared.noteDeleted(id: trade.id, owner: viewerID)

        XCTAssertNil(cache.trade(id: trade.id))
        XCTAssertTrue((cache.publicTrades(for: viewerID) ?? []).isEmpty)
    }

    func testAccountPatchUpdatesDashboardDiskCache() throws {
        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(BackendV2ContractFixtures.dashboard.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboard(dashboard, viewerID: viewerID.rawValue)

        var account = TradingAccount(
            id: TradingAccountID("33333333-3333-3333-3333-333333333333"),
            ownerProfileID: viewerID,
            name: "Renamed",
            category: .personal,
            mode: .live,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true
        )
        AccountPersistedCacheCoordinator.noteAccountPatched(account, viewerID: viewerID)

        let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: viewerID.rawValue)
        let row = cached?.bootstrap.data.accounts.first { $0.id == account.id.rawValue }
        XCTAssertEqual(row?.name, "Renamed")
    }

    func testOwnerTradeCompletenessBlocksPartialHistorySeed() {
        let metadata = OwnerTradeCacheCompleteness.metadata(
            historyComplete: false,
            totalTradeCount: 600,
            cachedTrades: Array(repeating: ProfileTradeFixtures.samples(owner: viewerID)[0], count: 500)
        )
        XCTAssertFalse(OwnerTradeCacheCompleteness.canSeedTradeHistoryFirstPage(
            metadata: metadata,
            seededItemCount: 40
        ))
    }

    func testOwnerTradeCompletenessAllowsCompleteHistorySeed() {
        let trades = [ProfileTradeFixtures.samples(owner: viewerID)[0]]
        let metadata = OwnerTradeCacheCompleteness.metadata(
            historyComplete: true,
            totalTradeCount: 1,
            cachedTrades: trades
        )
        XCTAssertTrue(OwnerTradeCacheCompleteness.canSeedTradeHistoryFirstPage(
            metadata: metadata,
            seededItemCount: 1
        ))
    }

    func testForceSoftStaleForTesting() throws {
        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(BackendV2ContractFixtures.dashboard.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboard(dashboard, viewerID: viewerID.rawValue)
        BackendV2BootstrapDiskCache.forceSoftStaleForTesting(viewerID: viewerID.rawValue)
        let loaded = BackendV2BootstrapDiskCache.loadDashboard(viewerID: viewerID.rawValue)
        XCTAssertEqual(loaded?.freshness, .softStale)
    }
}
