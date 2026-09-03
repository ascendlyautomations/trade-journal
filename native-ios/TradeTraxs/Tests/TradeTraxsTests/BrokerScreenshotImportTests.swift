import XCTest
@testable import TradeTraxs

final class BrokerScreenshotImportTests: XCTestCase {
    func testFixtureAExecutionHistoryClassifiesAsExecutions() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.executionOrderHistory
        )
        XCTAssertEqual(ScreenshotTableClassifier.classify(table: tables[0]), .executions)
    }

    func testFixtureAFilledRowsExtractedCancelledIgnored() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.executionOrderHistory
        )
        let exec = ScreenshotExecutionHistoryParser.parse(tables: tables)
        let result = ScreenshotTradeImportPipeline.process(
            blocksByImage: BrokerScreenshotFixtures.executionOrderHistory
        )
        XCTAssertEqual(exec.ignoredCancelledRows, 2)
        XCTAssertEqual(exec.fills.count, 5)
        XCTAssertTrue(exec.fills.allSatisfy { $0.quantity > 0 })
        XCTAssertFalse(exec.fills.contains(where: { $0.quantity == 0 }))
        XCTAssertGreaterThan(result.summary.trades.count, 0)
        XCTAssertLessThan(result.summary.trades.count, exec.fills.count, "Fills should aggregate — not one trade per row")
        XCTAssertTrue(
            result.metadataByTradeID.values.contains(where: { $0.aggregationSource == .fillAggregation })
        )
    }

    func testFixtureBCompletedTradeHistoryClassifiesCorrectly() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.completedTradeHistory
        )
        XCTAssertEqual(ScreenshotTableClassifier.classify(table: tables[0]), .completedTrades)
    }

    func testFixtureBEachRowBecomesCompletedCandidate() {
        let result = ScreenshotTradeImportPipeline.process(
            blocksByImage: BrokerScreenshotFixtures.completedTradeHistory
        )
        XCTAssertEqual(result.summary.trades.count, 3)
        let first = result.summary.trades[0]
        XCTAssertEqual(first.symbol, "MNQ")
        XCTAssertEqual(first.side, .long)
        XCTAssertEqual(NSDecimalNumber(decimal: first.quantity).intValue, 1)
        XCTAssertEqual(NSDecimalNumber(decimal: first.entryPrice ?? 0).doubleValue, 29_196.25, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: first.exitPrice ?? 0).doubleValue, 29_172.50, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: first.realizedPnL).doubleValue, -47.50, accuracy: 0.01)
    }

    func testFixtureCParserCandidatesUseExplicitSide() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.completedTradeTable
        )
        let parsed = ScreenshotCompletedTradeParser.parse(tables: tables)
        let mgc = parsed.candidates.first { $0.symbol == "MGC" }
        XCTAssertEqual(mgc?.side, .short, "cells=\(tables[0].dataRows.first?.allCellTexts ?? []) values=\(tables[0].dataRows.first?.values ?? [:])")
    }

    func testFixtureCCompletedTradeTableNormalizesSymbolsAndDirection() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.completedTradeTable
        )
        XCTAssertEqual(ScreenshotTableClassifier.classify(table: tables[0]), .completedTrades)

        let result = ScreenshotTradeImportPipeline.process(
            blocksByImage: BrokerScreenshotFixtures.completedTradeTable
        )
        XCTAssertEqual(result.summary.trades.count, 2)

        let mgc = result.summary.trades.first { $0.symbol == "MGC" }
        XCTAssertNotNil(mgc)
        XCTAssertEqual(mgc?.side, .short)
        XCTAssertEqual(NSDecimalNumber(decimal: mgc?.quantity ?? 0).doubleValue, 2, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: mgc?.entryPrice ?? 0).doubleValue, 4481.80, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: mgc?.exitPrice ?? 0).doubleValue, 4481.50, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: mgc?.realizedPnL ?? 0).doubleValue, 6, accuracy: 0.01)

        let mnq = result.summary.trades.first { $0.symbol == "MNQ" }
        XCTAssertNotNil(mnq)
        XCTAssertEqual(mnq?.side, .long)
    }

    func testThreeFixturesDoNotShareClassification() {
        let kinds = [
            BrokerScreenshotFixtures.executionOrderHistory,
            BrokerScreenshotFixtures.completedTradeHistory,
            BrokerScreenshotFixtures.completedTradeTable,
        ].map { blocks in
            let table = ScreenshotTradeTableReconstructor.reconstructStructured(blocksByImage: blocks)[0]
            return ScreenshotTableClassifier.classify(table: table)
        }
        XCTAssertEqual(kinds[0], .executions)
        XCTAssertEqual(kinds[1], .completedTrades)
        XCTAssertEqual(kinds[2], .completedTrades)
        XCTAssertNotEqual(kinds[0], kinds[1])
    }

    func testSymbolNormalizationXCMEPrefix() {
        XCTAssertEqual(FuturesInstrumentRegistry.normalizeSymbol("XCME_CO MGC (Z26)"), "MGC")
        XCTAssertEqual(FuturesInstrumentRegistry.normalizeSymbol("XCME_Eq MNQ (U26)"), "MNQ")
    }

    func testDirectionNotInferredFromPricesForLosingLong() {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(
            blocksByImage: BrokerScreenshotFixtures.completedTradeHistory
        )
        let parsed = ScreenshotCompletedTradeParser.parse(tables: tables)
        let first = parsed.candidates.first
        XCTAssertEqual(first?.side, .long)
        XCTAssertLessThan(first?.exitPrice ?? 0, first?.entryPrice ?? 0)
    }
}
