import XCTest
@testable import TradeTraxs

final class ProfileTradesDisplayGroupingTests: XCTestCase {
    private let profileID = ProfileID("e432738b-47bd-439b-a669-c71082202895")
    private let sourceID = TradingAccountID("0693ad68-984a-4c87-b14e-125e5bab78a7")
    private let copyB = TradingAccountID("977fda74-dd2d-42f8-8947-818797f31378")
    private let copyC = TradingAccountID("27d939a6-2673-4c9d-96ac-1166838dfa60")

    private let entryAt = ISO8601.date(from: "2026-10-05T04:07:00.000Z")!
    private let createdAt = ISO8601.date(from: "2026-10-05T04:11:26.139Z")!

    func testProductionMNQCopyActionCollapsesToOneProfileCard() {
        let rows = mnqCopyBatch(accountModes: [.funded, .funded, .evaluation])
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: rows,
            filter: .all,
            sort: .newest
        )
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].id.rawValue, "d6aa7038-cea7-4625-9e52-bc8cb2e55997")
        XCTAssertEqual(visible[0].mode, .copyTraded)
        XCTAssertEqual(
            visible[0].copyTradePublicModeSummary,
            "Copy Traded across 3 accounts • 2 Funded • 1 Eval"
        )
    }

    func testTwoCopyActionsSameGroupRemainTwoCards() {
        let first = mnqCopyBatch()
        let second = mnqCopyBatch(
            entryOffsetSeconds: 3600,
            tradeIDPrefix: "second"
        )
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: first + second,
            filter: .all,
            sort: .newest
        )
        XCTAssertEqual(visible.count, 2)
    }

    func testCopiedAccountOrderDoesNotSplitGroup() {
        var rows = mnqCopyBatch()
        rows[1].copyTrade = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyC, copyB],
            copyTradingGroupID: "044dd34a-f234-42b2-a18f-bf50fa6f5071"
        )
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: rows,
            filter: .all,
            sort: .newest
        )
        XCTAssertEqual(visible.count, 1)
    }

    func testAppendPageRegroupsCombinedJournalItems() {
        let pageOne = Array(mnqCopyBatch().prefix(2))
        let pageTwo = [mnqCopyBatch()[2]]
        let combined = pageOne + pageTwo
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: combined,
            filter: .all,
            sort: .newest
        )
        XCTAssertEqual(visible.count, 1)
    }

    func testNormalPublicTradeStaysSingleCard() {
        let row = TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: TradeID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                ownerProfileID: profileID,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                realizedPnL: Money(amount: 10, currencyCode: "USD"),
                riskReward: 1,
                points: nil,
                quantity: 1,
                entryAt: entryAt,
                exitAt: nil,
                createdAt: createdAt,
                visibility: .public,
                publicCaption: nil,
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: .live,
                accountMode: .live,
                publicAccountBadge: nil,
                durationSeconds: nil,
                durationText: nil
            ),
            accountID: copyB,
            accountName: nil,
            strategy: nil,
            entryPrice: nil,
            exitPrice: nil,
            sessionLabel: nil,
            copyTrade: nil
        )
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: [row],
            filter: .all,
            sort: .newest
        )
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].symbol.ticker, "ES")
    }

    func testModeSummaryFromJournalRowsWithoutProfileAccountMap() {
        let rows = mnqCopyBatch(accountModes: [.funded, .funded, .evaluation])
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: rows,
            filter: .all,
            sort: .newest,
            accountModesByID: [:]
        )
        XCTAssertEqual(
            visible[0].copyTradePublicModeSummary,
            "Copy Traded across 3 accounts • 2 Funded • 1 Eval"
        )
    }

    private func mnqCopyBatch(
        entryOffsetSeconds: TimeInterval = 0,
        tradeIDPrefix: String = "mnq",
        accountModes: [TradingAccountMode?]? = nil
    ) -> [TradeOwnerJournalSummary] {
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "044dd34a-f234-42b2-a18f-bf50fa6f5071"
        )
        let entry = entryAt.addingTimeInterval(entryOffsetSeconds)
        let pairs: [(String, TradingAccountID)] = [
            ("d6aa7038-cea7-4625-9e52-bc8cb2e55997", sourceID),
            ("b6afceb2-46da-43f4-90ea-00e54b9b2fb0", copyB),
            ("5c0ecd0e-9936-4b2f-aa4f-536ff4dac24a", copyC),
        ]
        return pairs.enumerated().map { index, pair in
            let (baseID, accountID) = pair
            let id = tradeIDPrefix == "mnq"
                ? baseID
                : "00000000-0000-4000-8000-\(String(format: "%012x", index + 1))"
            let rowAccountMode = accountModes?[index] ?? nil
            return TradeOwnerJournalSummary(
                summary: TradeSummary(
                    id: TradeID(id),
                    ownerProfileID: profileID,
                    symbol: Symbol(ticker: "MNQ"),
                    side: .long,
                    realizedPnL: Money(amount: 60, currencyCode: "USD"),
                    riskReward: 3,
                    points: 5,
                    quantity: 1,
                    entryAt: entry,
                    exitAt: nil,
                    createdAt: createdAt,
                    visibility: .public,
                    publicCaption: "IFVG",
                    notePreview: "IFVG",
                    thumbnail: nil,
                    imageDisplayMode: .fit,
                    mode: .copyTraded,
                    accountMode: rowAccountMode,
                    publicAccountBadge: nil,
                    durationSeconds: 192,
                    durationText: "3m 12s"
                ),
                accountID: accountID,
                accountName: nil,
                strategy: nil,
                entryPrice: nil,
                exitPrice: nil,
                sessionLabel: nil,
                copyTrade: metadata
            )
        }
    }
}

