import XCTest
@testable import TradeTraxs

final class TradingCalendarCopyTradingDedupeTests: XCTestCase {
    func testCopyTradingAllScopeDedupesDayPnL() {
        let owner = ProfileID("11111111-1111-1111-1111-111111111111")
        let sourceID = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let copyB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let createdAt = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB],
            copyTradingGroupID: "group-1"
        )
        let rows: [TradeOwnerJournalSummary] = [
            journalRow(id: "copy-a", accountID: sourceID, metadata: metadata, createdAt: createdAt, owner: owner),
            journalRow(id: "copy-b", accountID: copyB, metadata: metadata, createdAt: createdAt, owner: owner),
        ]
        let trades = rows.map { TradeSummaryMapper.listMatchTrade(from: $0) }
        let groups = [
            CopyTradingGroup(
                id: "group-1",
                name: "Alpha",
                accountIDs: [sourceID.rawValue, copyB.rawValue],
                createdAt: "",
                updatedAt: ""
            ),
        ]
        let days = TradingCalendarAggregator.daySummaries(
            from: trades,
            accountFilter: .copyTradingAll,
            copyTradingGroups: groups
        )
        let totalPnL = days.values.reduce(Decimal(0)) { $0 + $1.netPnL }
        XCTAssertEqual(days.values.reduce(0) { $0 + $1.tradeCount }, 1)
        XCTAssertEqual(totalPnL, 100)
    }

    private func journalRow(
        id: String,
        accountID: TradingAccountID,
        metadata: CopyTradeJournalMetadata,
        createdAt: Date,
        owner: ProfileID
    ) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: TradeID(id),
                ownerProfileID: owner,
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                realizedPnL: Money(amount: 100, currencyCode: "USD"),
                riskReward: nil,
                points: nil,
                quantity: 1,
                entryAt: createdAt,
                exitAt: nil,
                createdAt: createdAt,
                visibility: .private,
                publicCaption: nil,
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: .copyTraded,
                accountMode: .funded,
                publicAccountBadge: nil,
                durationSeconds: nil,
                durationText: nil
            ),
            accountID: accountID,
            accountName: nil,
            strategy: nil,
            entryPrice: 100,
            exitPrice: 110,
            sessionLabel: nil,
            copyTrade: metadata
        )
    }
}