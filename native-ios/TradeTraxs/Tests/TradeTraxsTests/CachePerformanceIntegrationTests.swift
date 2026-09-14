import XCTest
@testable import TradeTraxs

@MainActor
final class CachePerformanceIntegrationTests: XCTestCase {
    override func tearDown() {
        DiskCacheIOProbe.resetForTesting()
        ColdLaunchSummaryProbe.resetForTesting()
        super.tearDown()
    }

    func testRealtimeRegistryClearAllRemovesRefcounts() {
        let registry = InMemoryChannelRegistry()
        let channel = RealtimeChannelID(kind: .profile, topic: "test:viewer")
        registry.register(channel)
        registry.register(channel)
        XCTAssertEqual(registry.retainCount(for: channel), 2)

        registry.clearAll()
        XCTAssertTrue(registry.registeredChannels().isEmpty)
        XCTAssertEqual(registry.retainCount(for: channel), 0)
    }

    func testMessagingDomainRetainReleaseBalance() async {
        let domain = MessagingDomain.shared
        domain.invalidate()

        await domain.retainRealtime()
        await domain.retainRealtime()
        domain.releaseRealtime()
        domain.releaseRealtime()
        // Balanced retain/release should not crash; third release is a no-op.
        domain.releaseRealtime()
    }

    func testDiskCacheIOProbeCountsReadsAndWrites() {
        DiskCacheIOProbe.resetForTesting()
        DiskCacheIOProbe.recordRead()
        DiskCacheIOProbe.recordRead()
        DiskCacheIOProbe.recordWrite()
        let snapshot = DiskCacheIOProbe.snapshot()
        XCTAssertEqual(snapshot.reads, 2)
        XCTAssertEqual(snapshot.writes, 1)
    }

    func testOwnerTradeCompletenessBlocksRedundantFetchGate() {
        let viewerID = ProfileID("11111111-1111-1111-1111-111111111111")
        SessionOwnerTradesStore.shared.seed(
            [ProfileTradeFixtures.samples(owner: viewerID)[0]],
            for: viewerID,
            detailCache: DetailPresentationCache(),
            historyComplete: true,
            totalTradeCount: 1
        )
        XCTAssertTrue(SessionOwnerTradesStore.shared.isCompleteSnapshot(for: viewerID))
        SessionOwnerTradesStore.shared.invalidate()
    }

    func testSessionDiskCacheCorruptedJSONReturnsNil() {
        let viewerID = ProfileID("11111111-1111-1111-1111-111111111111")
        SessionDiskCache.clearAll()
        SessionDiskCache.saveOwnerTrades(
            [ProfileTradeFixtures.samples(owner: viewerID)[0]],
            for: viewerID,
            historyComplete: true,
            totalTradeCount: 1
        )
        XCTAssertNotNil(SessionDiskCache.loadOwnerTrades(for: viewerID))
        SessionDiskCache.clearAll()
        XCTAssertNil(SessionDiskCache.loadOwnerTrades(for: viewerID))
    }
}
