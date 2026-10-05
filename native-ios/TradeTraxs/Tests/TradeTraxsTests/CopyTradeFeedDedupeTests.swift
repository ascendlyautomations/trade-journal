import XCTest
@testable import TradeTraxs

final class CopyTradeFeedDedupeTests: XCTestCase {
    private let userID = "11111111-1111-1111-1111-111111111111"
    private let source = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let copyB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private let copyC = "cccccccc-cccc-cccc-cccc-cccccccccccc"

    func testThreeCopyPostsCollapseToOneVisibleItem() {
        let rows = copyPostRows(createdOffsets: [0, 0, 0])
        let plan = CopyTradeFeedDedupe.plan(from: rows)
        XCTAssertEqual(plan.visiblePostIDs.count, 1)
    }

    func testPublicModeSummaryIncludesOnlyParticipatingModes() {
        let rows = copyPostRows(createdOffsets: [0, 0, 0])
        let plan = CopyTradeFeedDedupe.plan(from: rows)
        guard let postID = plan.visiblePostIDs.first,
              let summary = plan.publicModeSummaryByPostID[postID]
        else {
            return XCTFail("Expected representative copy post")
        }
        XCTAssertTrue(summary.contains("Copy Traded across"))
        XCTAssertTrue(summary.contains("3 accounts"))
        XCTAssertTrue(summary.contains("2 Funded"))
        XCTAssertTrue(summary.contains("1 Live"))
        XCTAssertFalse(summary.contains("0 Live"))
        XCTAssertFalse(summary.contains("0 Eval"))
    }

    func testSeparateCopyActionsRemainSeparate() {
        let batch1 = copyPostRows(idPrefix: "a", createdOffsets: [0, 0, 0], entryTime: "2026-06-01T12:00:00.000Z")
        let batch2 = copyPostRows(idPrefix: "b", createdOffsets: [0, 0, 0], entryTime: "2026-06-02T12:00:00.000Z")
        let plan = CopyTradeFeedDedupe.plan(from: batch1 + batch2)
        XCTAssertEqual(plan.visiblePostIDs.count, 2)
    }

    func testNormalTradePostsRemainSeparate() {
        let copyRows = copyPostRows(createdOffsets: [0, 0, 0])
        let normal = [normalTradeRow(id: "solo-post")]
        let plan = CopyTradeFeedDedupe.plan(from: copyRows + normal)
        XCTAssertEqual(plan.visiblePostIDs.count, 2)
        XCTAssertTrue(plan.visiblePostIDs.contains("solo-post"))
    }

    func testDifferentCreatedAtStillGroupsWithAuthoritativeStamp() {
        let rows = copyPostRows(createdOffsets: [0, 4, 9])
        let keys = rows.compactMap { CopyTradeFeedDedupe.parseLinkage($0) }.compactMap(CopyTradeFeedDedupe.batchKey(for:))
        XCTAssertEqual(Set(keys).count, 1)
        let plan = CopyTradeFeedDedupe.plan(from: rows)
        XCTAssertEqual(plan.visiblePostIDs.count, 1)
    }

    func testPaginationDoesNotReintroduceDisplayedCopyAction() {
        let rows = copyPostRows(createdOffsets: [0, 0, 0])
        let plan = CopyTradeFeedDedupe.plan(from: rows)
        let items = rows.map { row in
            FeedItem(
                id: row.id,
                kind: .trade,
                authorProfileID: ProfileID(userID),
                createdAt: ISO8601.date(from: row.created_at) ?? Date(),
                tradeID: TradeID(row.id),
                postID: nil,
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: nil,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false
            )
        }
        let filtered = CopyTradeFeedDedupe.filterItems(items, plan: plan)
        XCTAssertEqual(filtered.count, 1)

        let firstSummary = TradeSummary(
            id: TradeID(filtered[0].id),
            ownerProfileID: ProfileID(userID),
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            realizedPnL: Money(amount: 100, currencyCode: "USD"),
            riskReward: nil,
            points: nil,
            quantity: 1,
            entryAt: Date(),
            exitAt: nil,
            createdAt: Date(),
            visibility: .public,
            publicCaption: nil,
            notePreview: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            mode: .copyTraded,
            accountMode: .funded,
            publicAccountBadge: nil,
            durationSeconds: nil,
            durationText: nil,
            copyTradePublicModeSummary: plan.publicModeSummaryByPostID[filtered[0].id],
            copyTradeFeedBatchKey: plan.batchKeyByPostID[filtered[0].id]
        )
        let existing: [FeedTimelineEntry] = [.trade(filtered[0], firstSummary)]

        let duplicateItem = items[1]
        let dupSummary = firstSummary
        let incoming: [FeedTimelineEntry] = [.trade(duplicateItem, dupSummary)]

        let merged = CopyTradeFeedDedupe.mergeTimeline(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.count, 1)
    }

    // MARK: - Fixtures

    private func copyPostRows(
        idPrefix: String = "copy",
        createdOffsets: [Int],
        entryTime: String = "2026-06-01T12:00:00.000Z"
    ) -> [FeedItemV1] {
        let accounts = [
            (source, "funded"),
            (copyB, "funded"),
            (copyC, "live"),
        ]
        let baseCreated = ISO8601.date(from: "2026-06-01T12:00:00.000Z") ?? Date()
        return zip(accounts, createdOffsets).enumerated().map { index, pair in
            let (accountID, mode) = pair.0
            let offset = pair.1
            let created = baseCreated.addingTimeInterval(TimeInterval(offset))
            return tradeFeedRow(
                id: "\(idPrefix)-post-\(index)",
                accountID: accountID,
                mode: mode,
                entryTime: entryTime,
                createdAt: ISO8601.string(from: created)
            )
        }
    }

    private func normalTradeRow(id: String) -> FeedItemV1 {
        tradeFeedRow(
            id: id,
            accountID: source,
            mode: "live",
            entryTime: "2026-07-01T12:00:00.000Z",
            createdAt: "2026-07-01T12:00:00.000Z",
            tradeMode: "live"
        )
    }

    private func tradeFeedRow(
        id: String,
        accountID: String,
        mode: String,
        entryTime: String,
        createdAt: String,
        tradeMode: String = "copy_traded"
    ) -> FeedItemV1 {
        FeedItemV1(
            kind: "trade",
            id: id,
            created_at: createdAt,
            author_id: userID,
            payload: [
                "trade_id": .string(id),
                "user_id": .string(userID),
                "trades": .object([
                    "user_id": .string(userID),
                    "account_id": .string(accountID),
                    "source_account_id": .string(source),
                    "copied_account_ids": .array([.string(copyB), .string(copyC)]),
                    "ticker": .string("NQ"),
                    "direction": .string("Long"),
                    "mode": .string(mode),
                    "trade_mode": .string(tradeMode),
                    "entry_time": .string(entryTime),
                    "created_at": .string(createdAt),
                ]),
            ]
        )
    }
}
