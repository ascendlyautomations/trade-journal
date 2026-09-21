import XCTest
@testable import TradeTraxs

final class TradeSummaryOwnerJournalTests: XCTestCase {
    func testOwnerJournalWireDecodeAndMapsExtensionFields() throws {
        let json = """
        {
          "summary_schema": "trade_summary_v1",
          "id": "00000000-0000-4000-8000-000000000301",
          "user_id": "00000000-0000-4000-8000-000000000001",
          "ticker": "MNQ",
          "direction": "Long",
          "pnl": 437,
          "rr": 2.9,
          "points": 21.75,
          "contracts": 2,
          "entry_time": "2026-08-11T14:32:00Z",
          "exit_time": "2026-08-11T14:36:32Z",
          "created_at": "2026-08-11T14:32:00Z",
          "is_public": false,
          "note_preview": "Waited for liquidity sweep",
          "account_id": "acc-1",
          "account_name": "Alpha 50K",
          "strategy": "ORB",
          "entry_price": 21452.25,
          "exit_price": 21474,
          "session": "NY"
        }
        """
        let wire = try JSONDecoder().decode(TradeOwnerJournalSummaryWireV1.self, from: Data(json.utf8))
        let summary = try TradeSummaryMapper.mapOwnerJournal(from: wire)
        XCTAssertEqual(summary.summary.symbol.ticker, "MNQ")
        XCTAssertEqual(summary.accountID?.rawValue, "acc-1")
        XCTAssertEqual(summary.accountName, "Alpha 50K")
        XCTAssertEqual(summary.strategy, "ORB")
        XCTAssertEqual(summary.sessionLabel, "NY")
    }

    func testJournalSummaryV2NotProductionShipped() {
        XCTAssertFalse(BackendV2FeatureFlags.productionShippedFlags.contains(.tradeJournalSummaryV2))
    }

    func testDetailMutationMapsBackToOwnerJournalSummary() {
        let detail = Trade(
            id: TradeID("t1"),
            ownerProfileID: ProfileID("u1"),
            accountID: TradingAccountID("a1"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_100),
            realizedPnL: Money(amount: 50),
            riskReward: Decimal(string: "2"),
            points: Decimal(string: "1"),
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: "preview",
            notes: "full notes should not be required for summary patch",
            strategy: "Breakout",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let summary = TradeSummaryMapper.ownerJournal(from: detail)
        XCTAssertEqual(summary.summary.notePreview, "preview")
        XCTAssertEqual(summary.strategy, "Breakout")
    }
}
