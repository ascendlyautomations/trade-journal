import XCTest
@testable import TradeTraxs

@MainActor
final class OwnerTradeCachePhase5Tests: XCTestCase {
    private let viewerID = ProfileID("11111111-1111-1111-1111-111111111111")
    private let otherViewerID = ProfileID("22222222-2222-2222-2222-222222222222")

    override func tearDown() {
        BackendV2BootstrapDiskCache.clearAll()
        SessionDiskCache.clearAll()
        SessionOwnerTradesStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        #if DEBUG
        TradeHistoryCacheProbe.resetForTesting()
        CalendarCacheProbe.resetForTesting()
        #endif
        super.tearDown()
    }

    func testHydrateFromDashboardDiskRestoresCompletenessWithoutFreshTTL() throws {
        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(BackendV2ContractFixtures.dashboard.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboard(dashboard, viewerID: viewerID.rawValue)

        let cache = DetailPresentationCache()
        let result = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: viewerID,
            detailCache: cache
        )

        XCTAssertTrue(result.hydrated)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.tradeCount, 1)
        XCTAssertFalse(SessionOwnerTradesStore.shared.isFresh(for: viewerID))
        XCTAssertTrue(SessionOwnerTradesStore.shared.isCompleteSnapshot(for: viewerID))

        let seeded = TradeHistoryOwnerSeed.page(
            from: SessionOwnerTradesStore.shared.cached(for: viewerID) ?? [],
            query: TradeHistoryQuery(),
            limit: 40
        )
        XCTAssertTrue(OwnerTradeCacheCompleteness.canSeedTradeHistoryFirstPage(
            metadata: SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID),
            seededItemCount: seeded.items.count
        ))
    }

    func testPartialSnapshotBlocksTradeHistoryFirstPageSeed() {
        let trades = (0..<500).map { index in
            makeTrade(id: "t-\(index)", owner: viewerID, createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        SessionOwnerTradesStore.shared.seed(
            trades,
            for: viewerID,
            detailCache: DetailPresentationCache(),
            historyComplete: false,
            totalTradeCount: 600
        )

        XCTAssertFalse(SessionOwnerTradesStore.shared.isCompleteSnapshot(for: viewerID))
        XCTAssertFalse(OwnerTradeCacheCompleteness.canSeedTradeHistoryFirstPage(
            metadata: SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID),
            seededItemCount: 40
        ))
    }

    func testCompleteOwnerCacheSupportsLocalPagination() {
        var trades: [Trade] = []
        for index in 0..<80 {
            trades.append(makeTrade(
                id: "p-\(index)",
                owner: viewerID,
                createdAt: Date(timeIntervalSince1970: Double(10_000 - index))
            ))
        }
        SessionOwnerTradesStore.shared.seed(
            trades,
            for: viewerID,
            detailCache: DetailPresentationCache(),
            historyComplete: true,
            totalTradeCount: 80
        )

        XCTAssertTrue(OwnerTradeCacheCompleteness.canPaginateFromOwnerCache(
            metadata: SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID)
        ))

        let first = TradeHistoryOwnerSeed.page(
            from: trades,
            query: TradeHistoryQuery(),
            limit: 40
        )
        let second = TradeHistoryOwnerSeed.page(
            from: trades,
            query: TradeHistoryQuery(),
            limit: 80
        )
        XCTAssertEqual(first.items.count, 40)
        XCTAssertNotNil(first.nextCursor)
        XCTAssertEqual(second.items.count, 80)
        XCTAssertNil(second.nextCursor)

        let firstIDs = Set(first.items.map(\.id))
        let secondOnly = second.items.filter { !firstIDs.contains($0.id) }
        XCTAssertEqual(secondOnly.count, 40)
        XCTAssertTrue(Set(second.items.map(\.id)).isDisjoint(with: []))
    }

    func testCalendarMonthSeedFromCompleteOwnerCache() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        let entry = calendar.date(from: DateComponents(
            timeZone: TradingCalendarDay.timeZone,
            year: 2026,
            month: 8,
            day: 5,
            hour: 10
        ))!

        let trade = makeTrade(id: "cal-1", owner: viewerID, createdAt: entry, entryAt: entry)
        SessionOwnerTradesStore.shared.seed(
            [trade],
            for: viewerID,
            detailCache: DetailPresentationCache(),
            historyComplete: true,
            totalTradeCount: 1
        )

        let monthTrades = OwnerTradeCalendarSeed.trades(
            from: SessionOwnerTradesStore.shared.cached(for: viewerID) ?? [],
            year: 2026,
            month: 8
        )
        XCTAssertEqual(monthTrades?.count, 1)
        XCTAssertTrue(OwnerTradeCacheCompleteness.canSeedCalendarMonth(
            metadata: SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID)
        ))
    }

    func testTradeCreatePropagatesToOwnerCache() {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        SessionOwnerTradesStore.shared.seed(
            [],
            for: viewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 0
        )

        let created = makeTrade(id: "new-1", owner: viewerID, createdAt: Date())
        TradeJournalMutationStore.shared.noteCreated(created)

        XCTAssertEqual(SessionOwnerTradesStore.shared.cached(for: viewerID)?.count, 1)
        XCTAssertEqual(SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID)?.totalTradeCount, 1)
        XCTAssertNotNil(cache.trade(id: created.id))
    }

    func testTradeEditPropagatesToOwnerCache() {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        var trade = makeTrade(id: "edit-1", owner: viewerID, createdAt: Date())
        SessionOwnerTradesStore.shared.seed(
            [trade],
            for: viewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 1
        )

        trade.realizedPnL = Money(amount: 999)
        TradeJournalMutationStore.shared.noteUpdated(trade)

        XCTAssertEqual(
            SessionOwnerTradesStore.shared.cached(for: viewerID)?.first?.realizedPnL?.amount,
            999
        )
        XCTAssertEqual(SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID)?.totalTradeCount, 1)
    }

    func testTradeDeletePropagatesToOwnerCache() {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        let trade = makeTrade(id: "del-1", owner: viewerID, createdAt: Date())
        SessionOwnerTradesStore.shared.seed(
            [trade],
            for: viewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 1
        )

        TradeJournalMutationStore.shared.noteDeleted(id: trade.id, owner: viewerID)

        XCTAssertTrue(SessionOwnerTradesStore.shared.cached(for: viewerID)?.isEmpty ?? false)
        XCTAssertEqual(SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID)?.totalTradeCount, 0)
    }

    func testBulkImportInvalidatesOwnerCache() {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        SessionOwnerTradesStore.shared.seed(
            [makeTrade(id: "bulk-1", owner: viewerID, createdAt: Date())],
            for: viewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 1
        )

        TradeJournalMutationStore.shared.noteBulkImport(owner: viewerID)

        XCTAssertNil(SessionOwnerTradesStore.shared.cached(for: viewerID))
        XCTAssertNil(SessionOwnerTradesStore.shared.snapshotMetadata(for: viewerID))
    }

    func testAccountSwitchIsolationClearsInMemoryOwnerTrades() {
        let cache = DetailPresentationCache()
        SessionOwnerTradesStore.shared.seed(
            [makeTrade(id: "a", owner: viewerID, createdAt: Date())],
            for: viewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 1
        )
        SessionOwnerTradesStore.shared.seed(
            [makeTrade(id: "b", owner: otherViewerID, createdAt: Date())],
            for: otherViewerID,
            detailCache: cache,
            historyComplete: true,
            totalTradeCount: 1
        )

        SessionOwnerTradesStore.shared.invalidate(profileID: viewerID)

        XCTAssertNil(SessionOwnerTradesStore.shared.cached(for: viewerID))
        XCTAssertEqual(SessionOwnerTradesStore.shared.cached(for: otherViewerID)?.count, 1)
    }

    func testSessionDiskCachePersistsCompletenessMetadata() {
        let trades = [makeTrade(id: "disk-1", owner: viewerID, createdAt: Date())]
        SessionDiskCache.saveOwnerTrades(
            trades,
            for: viewerID,
            historyComplete: true,
            totalTradeCount: 1
        )

        let blob = SessionDiskCache.loadOwnerTrades(for: viewerID)
        XCTAssertEqual(blob?.trades.count, 1)
        XCTAssertEqual(blob?.historyComplete, true)
        XCTAssertEqual(blob?.totalTradeCount, 1)
    }

    func testCorruptedCacheProfileMismatchReturnsNil() {
        let trades = [makeTrade(id: "bad-1", owner: viewerID, createdAt: Date())]
        SessionDiskCache.saveOwnerTrades(trades, for: viewerID, historyComplete: true, totalTradeCount: 1)

        let blob = SessionDiskCache.loadOwnerTrades(for: otherViewerID)
        XCTAssertNil(blob)
    }

    func testOwnerSeedMarksPartialWhenWindowCapped() {
        let trades = (0..<500).map { index in
            makeTrade(id: "cap-\(index)", owner: viewerID, createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        let result = TradeHistoryOwnerSeed.page(
            from: trades,
            query: TradeHistoryQuery(),
            limit: 40
        )
        XCTAssertTrue(result.isPartial)
    }

    // MARK: - Helpers

    private func makeTrade(
        id: String,
        owner: ProfileID,
        createdAt: Date,
        entryAt: Date? = nil
    ) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: entryAt ?? createdAt,
            exitAt: nil,
            realizedPnL: Money(amount: 10, currencyCode: "USD"),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            strategy: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
