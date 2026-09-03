import XCTest
@testable import TradeTraxs

final class ScreenshotImportExperienceTests: XCTestCase {
    private var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    func testTradeHistoryTableParsesMultipleTrades() {
        let summary = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.tradeHistoryTable
        ).summary
        XCTAssertEqual(summary.format, .screenshot)
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.trades[0].symbol, "MNQ")
        XCTAssertEqual(summary.trades[0].side, .long)
        XCTAssertEqual(summary.trades[1].symbol, "ES")
        XCTAssertEqual(summary.trades[1].side, .short)
    }

    func testPointsCalculationFromEntryExit() {
        let summary = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.tradeHistoryTable
        ).summary
        let mnq = summary.trades.first { $0.symbol == "MNQ" }
        XCTAssertNotNil(mnq?.entryPrice)
        XCTAssertNotNil(mnq?.exitPrice)
        XCTAssertNotNil(mnq?.points)
        let pointsValue = NSDecimalNumber(decimal: mnq?.points ?? 0).doubleValue
        XCTAssertEqual(pointsValue, 25.25, accuracy: 0.001)
    }

    func testDurationCalculationWhenExitTimePresent() {
        let summary = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.tradeHistoryTable
        ).summary
        let mnq = summary.trades.first { $0.symbol == "MNQ" }
        XCTAssertNotNil(mnq?.exitAt, "Expected exit time from screenshot row")
        XCTAssertNotNil(mnq?.durationSeconds, "Expected duration from entry/exit times")
        XCTAssertGreaterThan(mnq?.durationSeconds ?? 0, 0)
    }

    func testMissingPnLRequiresReview() {
        let summary = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.missingPnL
        ).summary
        XCTAssertEqual(summary.successCount, 1)
        let trade = summary.trades[0]
        XCTAssertEqual(trade.status, .needsReview)
        XCTAssertTrue(trade.warningMessages.contains("P&L missing"))
    }

    func testExecutionLinesAggregateToRoundTrip() {
        let result = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.executionLines
        )
        XCTAssertEqual(result.summary.successCount, 1)
        let trade = result.summary.trades[0]
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.side, .long)
        XCTAssertEqual(NSDecimalNumber(decimal: trade.quantity).doubleValue, 3, accuracy: 0.001)
        XCTAssertEqual(result.metadataByTradeID[trade.id]?.aggregationSource, .fillAggregation)
    }

    func testMultiScreenshotDedupesOverlappingRow() {
        let summary = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.multiScreenshotOverlap
        ).summary
        let mnqCount = summary.trades.filter { $0.symbol == "MNQ" }.count
        XCTAssertEqual(mnqCount, 1, "Duplicate MNQ row across screenshots should dedupe")
        XCTAssertEqual(summary.trades.filter { $0.symbol == "NQ" }.count, 1)
    }

    func testBatchDedupFingerprintUsesExecutionID() {
        let first = ScreenshotParsedCandidate(
            id: "a",
            kind: .completedTrade,
            symbol: "MNQ",
            side: .long,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: 10,
            points: nil,
            executionID: "EX-1",
            orderID: nil,
            warnings: [],
            sourceImageIndex: 0,
            sourceRowIndex: 0
        )
        let duplicate = ScreenshotParsedCandidate(
            id: "b",
            kind: .completedTrade,
            symbol: "MNQ",
            side: .long,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: 10,
            points: nil,
            executionID: "EX-1",
            orderID: nil,
            warnings: [],
            sourceImageIndex: 1,
            sourceRowIndex: 1
        )
        let deduped = ScreenshotTradeBatchDedup.dedupe([first, duplicate])
        XCTAssertEqual(deduped.count, 1)
    }

    func testTableReconstructorGroupsRowsByYPosition() {
        let rows = ScreenshotTradeTableReconstructor.reconstruct(
            blocksByImage: ScreenshotImportFixtures.tradeHistoryTable
        )
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        XCTAssertEqual(rows[1].cells.first, "MNQ")
    }

    @MainActor
    func testViewModelImportUsesBulkRepository() async {
        let repository = ScreenshotImportStubRepository()
        let cache = DetailPresentationCache()
        let owner = ProfileID("dev.screenshot.tests")
        cache.seed(accounts: PropFirmFixtures.accounts(owner: owner), for: owner)
        let viewModel = ScreenshotImportViewModel(
            trades: repository,
            session: ScreenshotImportStubSession(userID: owner.rawValue),
            detailCache: cache,
            onDismiss: {}
        )
        viewModel.ingestBlocksForTesting(ScreenshotImportFixtures.tradeHistoryTable)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.phase, .preview)
        viewModel.selectAccount(viewModel.eligibleAccounts[0].id)
        viewModel.importTrades()
        try? await Task.sleep(nanoseconds: 300_000_000)
        if case .result(let result) = viewModel.phase {
            XCTAssertGreaterThan(result.importedCount, 0)
            XCTAssertGreaterThan(repository.importedDrafts.count, 0)
            XCTAssertNil(repository.importedDrafts.first?.imageURL)
        } else {
            XCTFail("Expected import result, got \(viewModel.phase)")
        }
    }

    @MainActor
    func testUserEditUpdatesTradeInSummary() async {
        let repository = ScreenshotImportStubRepository()
        let viewModel = ScreenshotImportViewModel(
            trades: repository,
            session: ScreenshotImportStubSession(userID: "dev.edit"),
            detailCache: DetailPresentationCache(),
            onDismiss: {}
        )
        viewModel.ingestBlocksForTesting(ScreenshotImportFixtures.missingPnL)
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard var trade = viewModel.summary?.trades.first else {
            return XCTFail("Missing trade")
        }
        trade.realizedPnL = 150
        trade.warningMessages = []
        viewModel.updateTrade(trade)
        let updated = viewModel.summary?.trades.first
        XCTAssertEqual(updated?.realizedPnL, 150)
        XCTAssertEqual(updated?.status, .ready)
    }

    func testCSVImportUnchangedAfterScreenshotFormatAdded() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "tradovate.csv",
            text: CSVImportFixtures.tradovateCSV
        )
        XCTAssertEqual(summary.format, .tradovate)
        XCTAssertEqual(summary.successCount, 3)
    }
}

private final class ScreenshotImportStubRepository: TradeRepository, @unchecked Sendable {
    var importedDrafts: [TradeDraft] = []

    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.notImplemented(feature: "save")
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

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        PropFirmFixtures.accounts(owner: profileID)
    }

    func importCSVTrades(_ drafts: [TradeDraft], isInitialImport: Bool) async throws -> Int {
        importedDrafts = drafts
        return drafts.count
    }
}

private struct ScreenshotImportStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}
