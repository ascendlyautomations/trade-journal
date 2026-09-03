import XCTest
@testable import TradeTraxs

final class TradeFillAggregatorTests: XCTestCase {
    private var baseDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 2
        components.hour = 10
        components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar.date(from: components)!
    }

    private func fill(
        _ id: String,
        symbol: String = "MNQ",
        action: ParsedTradeFill.Action,
        qty: Decimal,
        price: Decimal,
        offsetMinutes: Int = 0,
        executionID: String? = nil,
        orderID: String? = nil,
        reportedPnL: Decimal? = nil,
        commission: Decimal? = nil
    ) -> ParsedTradeFill {
        ParsedTradeFill(
            id: id,
            symbol: symbol,
            action: action,
            quantity: qty,
            price: price,
            executedAt: baseDate.addingTimeInterval(TimeInterval(offsetMinutes * 60)),
            reportedPnL: reportedPnL,
            commission: commission,
            executionID: executionID,
            orderID: orderID,
            sourcePlatform: .generic,
            sourceImageIndex: 0,
            sourceRowIndex: Int(id.filter(\.isNumber)) ?? 0,
            warnings: []
        )
    }

    private func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value))!
    }

    // 1. Simple long
    func testSimpleLongAggregation() {
        let fills = [
            fill("1", action: .buy, qty: 2, price: 24100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 2, price: 24125, offsetMinutes: 5),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].side, .long)
        XCTAssertEqual(trips[0].quantity, 2)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].entryPrice).doubleValue, 24100, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].exitPrice).doubleValue, 24125, accuracy: 0.001)
    }

    // 2. Simple short
    func testSimpleShortAggregation() {
        let fills = [
            fill("1", action: .sell, qty: 1, price: 5000, offsetMinutes: 0),
            fill("2", action: .buy, qty: 1, price: 4990, offsetMinutes: 3),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].side, .short)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].exitPrice).doubleValue, 4990, accuracy: 0.001)
    }

    // 3. Scale-in
    func testScaleIn() {
        let fills = [
            fill("1", action: .buy, qty: 1, price: 100, offsetMinutes: 0),
            fill("2", action: .buy, qty: 2, price: 110, offsetMinutes: 1),
            fill("3", action: .sell, qty: 3, price: 120, offsetMinutes: 2),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].entryPrice).doubleValue, 106.666666, accuracy: 0.01)
    }

    // 4. Scale-out
    func testScaleOut() {
        let fills = [
            fill("1", action: .buy, qty: 3, price: 100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 1, price: 105, offsetMinutes: 1),
            fill("3", action: .sell, qty: 2, price: 110, offsetMinutes: 2),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].exitPrice).doubleValue, 108.333333, accuracy: 0.01)
    }

    // 5. Multiple entry + exit fills (spec example)
    func testMultipleEntryExitFillsSpecExample() {
        let fills = [
            fill("1", action: .buy, qty: 2, price: 24100, offsetMinutes: 0),
            fill("2", action: .buy, qty: 1, price: 24105, offsetMinutes: 1),
            fill("3", action: .sell, qty: 3, price: 24125, offsetMinutes: 2),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].entryPrice).doubleValue, 24101.666666, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].exitPrice).doubleValue, 24125, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[0].quantity).doubleValue, 3, accuracy: 0.001)
    }

    // 6–7. Weighted averages
    func testWeightedAverageEntryAndExit() {
        let entryLegs: [(Decimal, Decimal)] = [(24100, 2), (24105, 1)]
        let exitLegs: [(Decimal, Decimal)] = [(24120, 1), (24127.5, 2)]
        let avgEntry = TradeFillWeightedPrice.average(entryLegs.map { ($0.0, $0.1) })
        let avgExit = TradeFillWeightedPrice.average(exitLegs.map { ($0.0, $0.1) })
        XCTAssertEqual(NSDecimalNumber(decimal: avgEntry!).doubleValue, 24101.666666, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: avgExit!).doubleValue, 24125, accuracy: 0.01)
    }

    // 8. Position returns to zero
    func testPositionReturnsToZeroEmitsTrade() {
        let fills = [
            fill("1", action: .buy, qty: 1, price: 100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 1, price: 101, offsetMinutes: 1),
        ]
        XCTAssertEqual(TradeFillAggregator.aggregate(fills: fills).count, 1)
    }

    // 9. Position crosses through zero
    func testPositionCrossesThroughZero() {
        let fills = [
            fill("1", action: .buy, qty: 3, price: 100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 5, price: 102, offsetMinutes: 1),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].side, .long)
        XCTAssertEqual(trips[0].quantity, 3)
        XCTAssertEqual(trips[1].side, .short)
        XCTAssertEqual(NSDecimalNumber(decimal: trips[1].quantity).doubleValue, 2, accuracy: 0.001)
    }

    // 10. Multiple independent trades same symbol/day
    func testMultipleIndependentTradesSameSymbolDay() {
        let fills = [
            fill("1", action: .buy, qty: 1, price: 100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 1, price: 101, offsetMinutes: 1),
            fill("3", action: .buy, qty: 2, price: 102, offsetMinutes: 2),
            fill("4", action: .sell, qty: 2, price: 103, offsetMinutes: 3),
        ]
        XCTAssertEqual(TradeFillAggregator.aggregate(fills: fills).count, 2)
    }

    // 11. Multiple symbols interleaved
    func testMultipleSymbolsInterleaved() {
        let fills = [
            fill("1", symbol: "MNQ", action: .buy, qty: 1, price: 100, offsetMinutes: 0),
            fill("2", symbol: "ES", action: .buy, qty: 1, price: 5000, offsetMinutes: 1),
            fill("3", symbol: "MNQ", action: .sell, qty: 1, price: 101, offsetMinutes: 2),
            fill("4", symbol: "ES", action: .sell, qty: 1, price: 5005, offsetMinutes: 3),
        ]
        let trips = TradeFillAggregator.aggregate(fills: fills)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(Set(trips.map(\.symbol)), Set(["MNQ", "ES"]))
    }

    // 12. Duplicate execution IDs deduped
    func testDuplicateExecutionIDsRemoved() {
        let a = fill("1", action: .buy, qty: 1, price: 100, executionID: "EX-1")
        let b = fill("2", action: .buy, qty: 1, price: 100, executionID: "EX-1")
        let deduped = ScreenshotFillDedup.dedupe([a, b])
        XCTAssertEqual(deduped.unique.count, 1)
        XCTAssertEqual(deduped.removedCount, 1)
    }

    // 13. Screenshot overlap duplicates
    func testScreenshotOverlapDuplicates() {
        let a = fill("1", action: .buy, qty: 2, price: 24100, offsetMinutes: 0, executionID: "E1")
        var b = a
        b.id = "2"
        b.sourceImageIndex = 1
        let deduped = ScreenshotFillDedup.dedupe([a, b])
        XCTAssertEqual(deduped.unique.count, 1)
    }

    // 14. Same-looking but legitimate separate fills preserved
    func testLegitimateSimilarFillsPreserved() {
        let a = fill("1", action: .buy, qty: 1, price: 100, offsetMinutes: 0)
        let b = fill("2", action: .buy, qty: 1, price: 100, offsetMinutes: 5)
        let deduped = ScreenshotFillDedup.dedupe([a, b])
        XCTAssertEqual(deduped.unique.count, 2)
    }

    // 15–18. P&L calculation
    func testCalculatedMNQLongPnL() {
        guard let spec = FuturesInstrumentRegistry.resolve(symbol: "MNQ") else {
            return XCTFail("MNQ spec missing")
        }
        let pnl = FuturesInstrumentRegistry.grossPnL(
            spec: spec,
            side: .long,
            entryPrice: 24100,
            exitPrice: 24125,
            quantity: 3
        )
        XCTAssertEqual(NSDecimalNumber(decimal: pnl).doubleValue, 150, accuracy: 0.01)
    }

    func testCalculatedNQLongPnL() {
        guard let spec = FuturesInstrumentRegistry.resolve(symbol: "NQ") else {
            return XCTFail("NQ spec missing")
        }
        let pnl = FuturesInstrumentRegistry.grossPnL(
            spec: spec,
            side: .long,
            entryPrice: 20100,
            exitPrice: 20125,
            quantity: 1
        )
        XCTAssertEqual(NSDecimalNumber(decimal: pnl).doubleValue, 500, accuracy: 0.01)
    }

    func testShortPnLCalculation() {
        guard let spec = FuturesInstrumentRegistry.resolve(symbol: "ES") else {
            return XCTFail("ES spec missing")
        }
        let pnl = FuturesInstrumentRegistry.grossPnL(
            spec: spec,
            side: .short,
            entryPrice: 5012,
            exitPrice: 5008.25,
            quantity: 1
        )
        XCTAssertEqual(NSDecimalNumber(decimal: pnl).doubleValue, 187.5, accuracy: 0.01)
    }

    // 19. Reported vs calculated mismatch
    func testReportedVsCalculatedPnLMismatch() {
        let trip = TradeFillAggregator.aggregate(fills: [
            fill("1", action: .buy, qty: 1, price: 24100, offsetMinutes: 0),
            fill("2", action: .sell, qty: 1, price: 24125, offsetMinutes: 1, reportedPnL: 999),
        ]).first!
        let eval = ScreenshotPnLCalculator.evaluate(
            symbol: "MNQ",
            side: trip.side,
            quantity: trip.quantity,
            entryPrice: trip.entryPrice,
            exitPrice: trip.exitPrice,
            reportedPnL: 999,
            roundTrip: trip
        )
        XCTAssertTrue(eval.warnings.contains("Review P&L"))
    }

    // 20. Unknown instrument does not invent P&L
    func testUnknownInstrumentDoesNotInventPnL() {
        let eval = ScreenshotPnLCalculator.evaluate(
            symbol: "XYZ",
            side: .long,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            reportedPnL: nil
        )
        XCTAssertNil(eval.calculatedGrossPnL)
    }

    // 21–23. Duplicate detection
    func testExactJournalDuplicate() {
        let trade = CSVParsedTrade(
            id: "t1",
            rowNumber: 1,
            symbol: "MNQ",
            side: .long,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: baseDate,
            exitAt: baseDate.addingTimeInterval(300),
            realizedPnL: 20,
            riskReward: nil,
            points: 10,
            sessionLabel: "NY",
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: 300,
            status: .ready,
            warningMessages: []
        )
        let fingerprint = "v1:abc"
        let existing = Trade(
            id: TradeID("existing"),
            ownerProfileID: ProfileID("u1"),
            accountID: TradingAccountID("acc1"),
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: baseDate,
            exitAt: baseDate.addingTimeInterval(300),
            realizedPnL: Money(amount: 20),
            riskReward: nil,
            points: 10,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            importFingerprint: fingerprint,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        let classification = ImportDuplicateDetector.classify(
            candidate: .init(trade: trade, fingerprint: fingerprint, metadata: .empty()),
            existingTrades: [existing],
            accountID: TradingAccountID("acc1")
        )
        XCTAssertEqual(classification, ImportDuplicateClassification.exactDuplicate)
    }

    func testPossibleFuzzyDuplicate() {
        let trade = CSVParsedTrade(
            id: "t1",
            rowNumber: 1,
            symbol: "MNQ",
            side: .long,
            quantity: 2,
            entryPrice: 24100,
            exitPrice: 24125,
            entryAt: baseDate,
            exitAt: baseDate.addingTimeInterval(600),
            realizedPnL: 100,
            riskReward: nil,
            points: 25,
            sessionLabel: "NY",
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: 600,
            status: .ready,
            warningMessages: []
        )
        let existing = Trade(
            id: TradeID("existing"),
            ownerProfileID: ProfileID("u1"),
            accountID: TradingAccountID("acc1"),
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: 24100,
            exitPrice: 24125,
            entryAt: baseDate.addingTimeInterval(30),
            exitAt: baseDate.addingTimeInterval(630),
            realizedPnL: Money(amount: 100),
            riskReward: nil,
            points: 25,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        let classification = ImportDuplicateDetector.classify(
            candidate: .init(trade: trade, fingerprint: "v1:new", metadata: .empty()),
            existingTrades: [existing],
            accountID: TradingAccountID("acc1")
        )
        XCTAssertEqual(classification, ImportDuplicateClassification.possibleDuplicate)
    }

    func testNewTradeClassification() {
        let trade = CSVParsedTrade(
            id: "t1",
            rowNumber: 1,
            symbol: "ES",
            side: .short,
            quantity: 1,
            entryPrice: 5000,
            exitPrice: 4990,
            entryAt: baseDate,
            exitAt: baseDate.addingTimeInterval(120),
            realizedPnL: 50,
            riskReward: nil,
            points: 10,
            sessionLabel: "NY",
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: 120,
            status: .ready,
            warningMessages: []
        )
        let classification = ImportDuplicateDetector.classify(
            candidate: .init(trade: trade, fingerprint: "v1:new", metadata: .empty()),
            existingTrades: [],
            accountID: TradingAccountID("acc1")
        )
        XCTAssertEqual(classification, ImportDuplicateClassification.newTrade)
    }

    // 24. Pipeline + CSV unchanged
    func testExecutionLinesPipelineAggregates() {
        let result = ScreenshotTradeImportPipeline.process(
            blocksByImage: ScreenshotImportFixtures.executionLines
        )
        XCTAssertEqual(result.summary.trades.count, 1)
        let trade = result.summary.trades[0]
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.side, .long)
        XCTAssertEqual(NSDecimalNumber(decimal: trade.quantity).doubleValue, 3, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: trade.entryPrice ?? 0).doubleValue, 24101.666666, accuracy: 0.01)
        let metadata = result.metadataByTradeID[trade.id]
        XCTAssertEqual(metadata?.entryFillCount, 2)
        XCTAssertEqual(metadata?.exitFillCount, 1)
    }

    func testCSVImportUnchangedAfterScreenshotPhase2() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "tradovate.csv",
            text: CSVImportFixtures.tradovateCSV
        )
        XCTAssertEqual(summary.format, .tradovate)
        XCTAssertEqual(summary.successCount, 3)
    }
}
