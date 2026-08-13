import XCTest
@testable import TradeTraxs

@MainActor
final class SupabaseUsageReductionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        await SessionFollowingStore.shared.invalidate()
        SessionDiskCache.clearAll()
        SessionNetworkProbe.resetForTesting()
        SupabaseSessionUsage.resetForTesting()
    }

    override func tearDown() async throws {
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        await SessionFollowingStore.shared.invalidate()
        SessionDiskCache.clearAll()
        SessionNetworkProbe.resetForTesting()
        SupabaseSessionUsage.resetForTesting()
        try await super.tearDown()
    }

    func testFollowingStoreFetchesOnceAcrossConsumers() async throws {
        var fetchCount = 0
        let viewer = "viewer-1"
        let first = try await SessionFollowingStore.shared.followingIDs(viewerID: viewer) {
            fetchCount += 1
            return ["a", "b", "c"]
        }
        let second = try await SessionFollowingStore.shared.followingIDs(viewerID: viewer) {
            fetchCount += 1
            return ["should-not-run"]
        }
        XCTAssertEqual(Set(first), Set(["a", "b", "c"]))
        XCTAssertEqual(Set(second), Set(["a", "b", "c"]))
        XCTAssertEqual(fetchCount, 1)
    }

    func testOwnerTradesCacheHitSkipsNetwork() async throws {
        let owner = ProfileID("00000000-0000-4000-8000-000000000401")
        let cache = DetailPresentationCache()
        let trade = makeTrade("t-owner-1", owner: owner)
        let repo = CountingOwnerTradeRepository(trades: [trade])

        let first = try await SessionOwnerTradesStore.shared.trades(
            for: owner,
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(repo.pageCallCount, 1)

        let second = try await SessionOwnerTradesStore.shared.trades(
            for: owner,
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(repo.pageCallCount, 1)
    }

    func testDiskCacheRoundTripAccounts() {
        let owner = ProfileID("00000000-0000-4000-8000-000000000402")
        let account = TradingAccount(
            id: TradingAccountID("acc-1"),
            ownerProfileID: owner,
            name: "Main",
            category: .personal,
            mode: .live,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true
        )
        SessionDiskCache.saveAccounts([account], for: owner)
        let loaded = SessionDiskCache.loadAccounts(for: owner)
        XCTAssertEqual(loaded?.first?.id, account.id)
    }

    func testSessionUsageTracksCacheHits() {
        SupabaseSessionUsage.beginSession()
        SessionNetworkProbe.record(.cacheHit, resource: "profiles.batch", detail: "test")
        SessionNetworkProbe.record(.requestCoalesced, resource: "profiles.batch", detail: "test")
        let snap = SupabaseSessionUsage.snapshot()
        XCTAssertEqual(snap.cacheHits, 2)
        XCTAssertEqual(snap.requestsAvoided, 2)
        XCTAssertFalse(SupabaseSessionUsage.reportSummary().isEmpty)
    }

    // MARK: - Helpers

    private func makeTrade(_ id: String, owner: ProfileID) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class CountingOwnerTradeRepository: TradeRepository, @unchecked Sendable {
    private let trades: [Trade]
    private(set) var pageCallCount = 0

    init(trades: [Trade]) {
        self.trades = trades
    }

    func trade(id: TradeID) async throws -> Trade {
        trades.first { $0.id == id }!
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        pageCallCount += 1
        return CursorPage(items: trades, nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}
