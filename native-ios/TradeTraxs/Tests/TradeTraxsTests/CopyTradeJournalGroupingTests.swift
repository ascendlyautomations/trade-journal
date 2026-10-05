import XCTest
@testable import TradeTraxs

final class CopyTradeJournalGroupingTests: XCTestCase {
    private let profileID = ProfileID("11111111-1111-1111-1111-111111111111")
    private let sourceID = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let copyB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let copyC = TradingAccountID("cccccccc-cccc-cccc-cccc-cccccccccccc")
    private let unrelated = TradingAccountID("dddddddd-dddd-dddd-dddd-dddddddddddd")

    private let createdAt = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!
    private let createdAt2 = ISO8601.date(from: "2026-06-02T12:00:00.000Z")!

    private var accounts: [TradingAccount] {
        [
            makeAccount(id: sourceID, name: "Alpha Futures", mode: .funded, number: "100001234"),
            makeAccount(id: copyB, name: "Alpha Futures", mode: .funded, number: "100005678"),
            makeAccount(id: copyC, name: "TradeStation", mode: .live, number: "100009012"),
        ]
    }

    func testThreeCopyRowsCollapseToOneDisplayGroup() {
        let rows = copyBatchRows(createdAt: createdAt)
        let grouped = CopyTradeJournalGrouping.group(rows, accounts: accounts)
        XCTAssertEqual(grouped.count, 1)
        guard case .copyGroup(let group) = grouped[0] else {
            return XCTFail("Expected copy group")
        }
        XCTAssertEqual(group.members.count, 3)
    }

    func testParticipatingAccountsAllShownOnCard() {
        let rows = copyBatchRows(createdAt: createdAt)
        let grouped = CopyTradeJournalGrouping.group(rows, accounts: accounts)
        guard case .copyGroup(let group) = grouped[0] else {
            return XCTFail("Expected copy group")
        }
        XCTAssertEqual(group.participatingAccountLines.count, 3)
        XCTAssertTrue(group.participatingAccountLines[0].contains("Alpha Futures"))
        XCTAssertTrue(group.participatingAccountLines[0].contains("Funded"))
        XCTAssertTrue(group.participatingAccountLines[0].contains("••••1234"))
        XCTAssertTrue(group.participatingAccountLines[2].contains("TradeStation"))
    }

    func testAllAccountsFilterShowsOneCard() {
        let rows = copyBatchRows(createdAt: createdAt)
        let grouped = CopyTradeJournalGrouping.group(rows, accounts: accounts)
        XCTAssertEqual(grouped.count, 1)
    }

    func testEachParticipatingAccountFilterMatchesGroup() {
        let rows = copyBatchRows(createdAt: createdAt)
        for accountID in [sourceID, copyB, copyC] {
            var filters = TradeHistoryFilters()
            filters.account = .account(accountID)
            let query = TradeHistoryQuery(filters: filters)
            let filtered = rows.filter {
                TradeHistoryLocalMatch.matches(
                    TradeSummaryMapper.listMatchTrade(from: $0),
                    query: query
                )
            }
            XCTAssertEqual(filtered.count, 3, "All sibling rows match participating filter")
            let display = CopyTradeJournalGrouping.group(filtered, accounts: accounts)
            XCTAssertEqual(display.count, 1, "Expected one card for \(accountID.rawValue)")
            guard case .copyGroup(let group) = display[0] else {
                return XCTFail("Expected copy group")
            }
            XCTAssertEqual(group.participatingAccountLines.count, 3)
        }
    }

    func testUnrelatedAccountFilterExcludesCopyGroup() {
        let rows = copyBatchRows(createdAt: createdAt)
        var filters = TradeHistoryFilters()
        filters.account = .account(unrelated)
        let query = TradeHistoryQuery(filters: filters)
        let filtered = rows.filter {
            TradeHistoryLocalMatch.matches(
                TradeSummaryMapper.listMatchTrade(from: $0),
                query: query
            )
        }
        XCTAssertTrue(filtered.isEmpty)
        XCTAssertTrue(CopyTradeJournalGrouping.group(filtered, accounts: accounts).isEmpty)
    }

    func testSeparateCopyActionsRemainSeparate() {
        let batch1 = copyBatchRows(createdAt: createdAt)
        let batch2 = copyBatchRows(createdAt: createdAt2)
        let grouped = CopyTradeJournalGrouping.group(batch1 + batch2, accounts: accounts)
        XCTAssertEqual(grouped.count, 2)
    }

    func testNormalTradesRemainUngrouped() {
        let normal = makeJournalRow(
            id: "normal-1",
            accountID: sourceID,
            mode: .live,
            tradeMode: .live,
            copyTrade: nil
        )
        let grouped = CopyTradeJournalGrouping.group([normal], accounts: accounts)
        XCTAssertEqual(grouped.count, 1)
        guard case .single = grouped[0] else {
            return XCTFail("Expected single trade")
        }
    }

    // MARK: - Fixtures

    private func copyBatchRows(createdAt: Date) -> [TradeOwnerJournalSummary] {
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "group-1"
        )
        return [
            makeJournalRow(
                id: "copy-a",
                accountID: sourceID,
                mode: .funded,
                tradeMode: .copyTraded,
                copyTrade: metadata,
                createdAt: createdAt
            ),
            makeJournalRow(
                id: "copy-b",
                accountID: copyB,
                mode: .funded,
                tradeMode: .copyTraded,
                copyTrade: metadata,
                createdAt: createdAt
            ),
            makeJournalRow(
                id: "copy-c",
                accountID: copyC,
                mode: .live,
                tradeMode: .copyTraded,
                copyTrade: metadata,
                createdAt: createdAt
            ),
        ]
    }

    private func makeJournalRow(
        id: String,
        accountID: TradingAccountID,
        mode: TradingAccountMode,
        tradeMode: TradeMode,
        copyTrade: CopyTradeJournalMetadata?,
        createdAt: Date? = nil
    ) -> TradeOwnerJournalSummary {
        let created = createdAt ?? self.createdAt
        return TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: TradeID(id),
                ownerProfileID: profileID,
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                realizedPnL: Money(amount: 100, currencyCode: "USD"),
                riskReward: nil,
                points: nil,
                quantity: 1,
                entryAt: created,
                exitAt: nil,
                createdAt: created,
                visibility: .private,
                publicCaption: nil,
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: tradeMode,
                accountMode: mode,
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
            copyTrade: copyTrade
        )
    }

    private func makeAccount(
        id: TradingAccountID,
        name: String,
        mode: TradingAccountMode,
        number: String
    ) -> TradingAccount {
        TradingAccount(
            id: id,
            ownerProfileID: profileID,
            name: name,
            category: .propFirm,
            mode: mode,
            size: Money(amount: 50_000, currencyCode: "USD"),
            isActive: true,
            canAddTrades: true,
            accountNumber: number
        )
    }
}
