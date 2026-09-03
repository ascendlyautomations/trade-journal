import CoreGraphics
import ImageIO
import XCTest
@testable import TradeTraxs

/// Live Vision OCR against broker screenshots on disk (skipped when files are absent).
final class BrokerScreenshotLiveOCRTests: XCTestCase {
    private let executionPath = "/Users/TradeTraxs/Desktop/c54ed38a-0326-466e-a1db-3a721218f71e.png"
    private let completedHistoryPath = "/Users/TradeTraxs/Desktop/f1bc5279-4c6b-4d3b-b569-ef2e96f258c1.png"
    private let completedTablePath = "/Users/TradeTraxs/Desktop/eb4a6889-e393-42c5-b2f4-2ab7ee6c5176.png"

    func testLiveExecutionOrderHistoryScreenshot() async throws {
        try await runLive(path: executionPath, expectedKind: .executions)
    }

    func testLiveCompletedTradeHistoryScreenshot() async throws {
        try await runLive(path: completedHistoryPath, expectedKind: .completedTrades)
    }

    func testLiveCompletedTradeTableScreenshot() async throws {
        try await runLive(path: completedTablePath, expectedKind: .completedTrades)
    }

    private func runLive(path: String, expectedKind: ScreenshotTableKind) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Screenshot not found at \(path)")
        }
        guard let image = Self.loadCGImage(path: path) else {
            XCTFail("Could not load image at \(path)")
            return
        }

        let blocks = try await ScreenshotTradeOCRService.recognizeText(in: image)
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(blocksByImage: [blocks])
        let kind = ScreenshotTableClassifier.classify(table: tables[0])
        let result = ScreenshotTradeImportPipeline.process(blocksByImage: [blocks])

        let headers = tables[0].columns.map(\.headerText).joined(separator: ", ")
        let exec = ScreenshotExecutionHistoryParser.parse(tables: tables)
        let completed = ScreenshotCompletedTradeParser.parse(tables: tables)

        let summary = """
        kind=\(kind.rawValue) headers=[\(headers)] rows=\(tables[0].dataRows.count) \
        fills=\(exec.fills.count) ignoredCancelled=\(exec.ignoredCancelledRows) \
        completed=\(completed.candidates.count) trades=\(result.summary.trades.count) \
        rejected=\(exec.rejectedRows.count + completed.rejectedRows.count) \
        reasons=\(completed.rejectedRows.prefix(3).map(\.reason).joined(separator: ";"))
        """
        XCTAssertEqual(kind, expectedKind, summary)
        XCTAssertGreaterThan(result.summary.trades.count, 0, summary)
    }

    private static func loadCGImage(path: String) -> CGImage? {
        guard let data = FileManager.default.contents(atPath: path),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func testGenerateLiveDiagnosticsReport() async throws {
        let cases: [(String, String, ScreenshotTableKind)] = [
            ("Execution/Order History", executionPath, .executions),
            ("Completed Trade History", completedHistoryPath, .completedTrades),
            ("Completed Trade Table", completedTablePath, .completedTrades),
        ]

        var report = ""
        for (name, path, expectedKind) in cases {
            guard FileManager.default.fileExists(atPath: path),
                  let image = Self.loadCGImage(path: path)
            else {
                report += "\n## \(name)\nScreenshot file missing at \(path)\n"
                continue
            }

            let blocks = try await ScreenshotTradeOCRService.recognizeText(in: image)
            let tables = ScreenshotTradeTableReconstructor.reconstructStructured(blocksByImage: [blocks])
            let table = tables[0]
            let kind = ScreenshotTableClassifier.classify(table: table)
            let exec = ScreenshotExecutionHistoryParser.parse(tables: tables)
            let completed = ScreenshotCompletedTradeParser.parse(tables: tables)
            let result = ScreenshotTradeImportPipeline.process(blocksByImage: [blocks])

            let fields = result.summary.trades.prefix(3).map {
                "\($0.symbol) \($0.side.rawValue) qty=\($0.quantity) pnl=\($0.realizedPnL) warnings=\($0.warningMessages.joined(separator: ";"))"
            }.joined(separator: " | ")

            report += """

            ## \(name)
            1. classification: \(kind.rawValue) (expected \(expectedKind.rawValue))
            2. headers: \(table.columns.map(\.headerText).joined(separator: ", "))
            3. rows reconstructed: \(table.dataRows.count)
            4. rows ignored: cancelled=\(exec.ignoredCancelledRows) rejected=\(exec.rejectedRows.count + completed.rejectedRows.count)
            5. candidates: completed=\(completed.candidates.count) executionFills=\(exec.fills.count) importTrades=\(result.summary.trades.count)
            6. fields extracted: \(fields)
            7. review warnings: \(result.summary.trades.flatMap(\.warningMessages).uniqued().prefix(8).joined(separator: "; "))
            """
        }
        try report.write(toFile: "/tmp/screenshot_import_diag.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(true)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
