import XCTest
@testable import TradeTraxs

final class BrokerImportReconciliationTests: XCTestCase {
    func testAuthoritativeNewImportCountPrefersExplicitIDs() throws {
        let summary = try decodeSummary(
            """
            {"ok":true,"connectionId":"c","mappingId":"m","summary":{"ok":true,"status":"success","tradesCreated":2,"newTradeIds":["a","b"]}}
            """
        )
        XCTAssertEqual(summary.authoritativeNewImportCount, 2)
        XCTAssertEqual(summary.resolvedNewTradeIDs, ["a", "b"])
    }

    func testAuthoritativeNewImportCountFallsBackToTradesCreated() throws {
        let summary = try decodeSummary(
            """
            {"ok":true,"connectionId":"c","mappingId":"m","summary":{"ok":true,"status":"success","tradesCreated":3,"newTradeIds":[]}}
            """
        )
        XCTAssertEqual(summary.authoritativeNewImportCount, 3)
        XCTAssertTrue(summary.resolvedNewTradeIDs.isEmpty)
    }

    private func decodeSummary(_ json: String) throws -> TradovateSyncSummaryPayload {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(TradovateAccountSyncResponse.self, from: data)
        return response.summary
    }
}
