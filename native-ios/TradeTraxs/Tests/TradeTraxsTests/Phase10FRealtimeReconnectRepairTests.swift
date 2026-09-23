import XCTest
@testable import TradeTraxs

final class Phase10FRealtimeReconnectRepairTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

    override func tearDown() async throws {
        await SocialRealtimeReconciliationCoordinator.shared.reset()
        await SessionFollowingStore.shared.invalidate()
        try await super.tearDown()
    }

    func testReconnectTriggersSingleRepairCycle() async {
        await SocialRealtimeReconciliationCoordinator.shared.bindViewer(viewerA)
        await SocialRealtimeReconciliationCoordinator.shared.noteDisconnectObserved(activeRoutes: 2)
        await SocialRealtimeReconciliationCoordinator.shared.noteReconnectCompleted(activeRoutes: 2)
        await SocialRealtimeReconciliationCoordinator.shared.awaitIdleForTesting()
        let snap = await SocialRealtimeReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.viewerID, viewerA)
        XCTAssertTrue(snap.pending.isEmpty)
    }

    func testRepairSignalsCoalesce() async {
        await SocialRealtimeReconciliationCoordinator.shared.bindViewer(viewerA)
        await SocialRealtimeReconciliationCoordinator.shared.noteDisconnectObserved()
        await SocialRealtimeReconciliationCoordinator.shared.requestRepair(.realtimeReconnect)
        await SocialRealtimeReconciliationCoordinator.shared.requestRepair(.realtimeReconnect)
        await SocialRealtimeReconciliationCoordinator.shared.requestRepair(.realtimeReconnect)
        await SocialRealtimeReconciliationCoordinator.shared.awaitIdleForTesting()
        let snap = await SocialRealtimeReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertTrue(snap.pending.isEmpty)
    }

    func testNetworkRegainWithoutDisconnectSkipsRepair() async {
        await SocialRealtimeReconciliationCoordinator.shared.bindViewer(viewerA)
        await SocialRealtimeReconciliationCoordinator.shared.requestRepair(.networkRegain)
        await SocialRealtimeReconciliationCoordinator.shared.awaitIdleForTesting(timeout: .milliseconds(200))
        // No disconnect observed — repair should not schedule work (pending cleared without run).
        let snap = await SocialRealtimeReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertTrue(snap.pending.isEmpty)
    }

    func testAccountSwitchIncrementsGeneration() async {
        await SocialRealtimeReconciliationCoordinator.shared.bindViewer(viewerA)
        let before = await SocialRealtimeReconciliationCoordinator.shared.snapshotForTesting()
        await SocialRealtimeReconciliationCoordinator.shared.bindViewer(viewerB)
        let after = await SocialRealtimeReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(before.viewerID, viewerA)
        XCTAssertEqual(after.viewerID, viewerB)
        XCTAssertGreaterThan(after.generation, before.generation)
    }

    func testUnknownFollowingNeverTreatedAsEmpty() async {
        await SessionFollowingStore.shared.seedPairwiseEdge(
            viewerID: viewerA.rawValue,
            targetID: "target-1",
            isFollowing: true
        )
        let complete = await SessionFollowingStore.shared.cached(viewerID: viewerA.rawValue)
        XCTAssertNil(complete)
    }

    func testFeedHeadReconcilePreservesExistingEntries() {
        let author = ProfileID("author-1")
        let existing = [
            makeTradeEntry(id: "keep-1", author: author, age: 120),
            makeTradeEntry(id: "keep-2", author: author, age: 240),
        ]
        let incoming = [
            makeTradeEntry(id: "new-head", author: author, age: 10),
            makeTradeEntry(id: "keep-1", author: author, age: 120),
        ]
        let result = FeedPersistentReconcile.reconcileFirstPage(
            existing: existing,
            incoming: incoming
        )
        XCTAssertTrue(result.entries.contains { $0.id == "keep-2" })
        XCTAssertTrue(result.entries.contains { $0.id == "new-head" })
        XCTAssertEqual(result.inserted, 1)
    }

    @MainActor
    func testMessagingDedupeClaimSurvivesRepairContext() {
        MessagingRealtimeDeliveryCoordinator.resetSession()
        XCTAssertTrue(
            MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "repair",
                messageID: "m-repair",
                conversationID: "c1"
            )
        )
        XCTAssertFalse(
            MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "inbox-dm",
                messageID: "m-repair",
                conversationID: "c1"
            )
        )
    }

    private func makeTradeEntry(
        id: String,
        author: ProfileID,
        age: TimeInterval
    ) -> FeedTimelineEntry {
        let createdAt = Date(timeIntervalSinceNow: -age)
        let tradeID = TradeID("trade-\(id)")
        let trade = Trade(
            id: tradeID,
            ownerProfileID: author,
            accountID: nil,
            symbol: Symbol(ticker: "AAPL"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: createdAt,
            exitAt: createdAt.addingTimeInterval(3600),
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: id,
            thumbnail: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let item = FeedItem(
            id: id,
            kind: .trade,
            authorProfileID: author,
            createdAt: createdAt,
            tradeID: tradeID,
            postID: PostID(id),
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: id,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false
        )
        return .trade(item, TradeSummaryMapper.summary(fromPartialListTrade: trade))
    }
}
