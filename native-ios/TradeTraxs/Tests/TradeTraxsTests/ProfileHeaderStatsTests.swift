import XCTest
@testable import TradeTraxs

final class ProfileHeaderStatsTests: XCTestCase {
    func testSessionStubDoesNotCountAsLoadedHeaderMetrics() {
        let stub = ProfileStats(
            profileID: ProfileID("viewer"),
            followerCount: 0,
            followingCount: 5,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
        XCTAssertFalse(stub.hasLoadedHeaderMetrics)
        let metrics = ProfileDisplay.headerMetrics(from: stub)
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, ProfileHeaderMetric.placeholderValue)
    }

    func testRestStatsWithZeroTradesShowsZeroWinRateNotDash() {
        let overview = ProfileOverviewMetrics.compute(from: [])
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 1,
            followingCount: 1,
            postCount: 0,
            tradeCount: overview.publicTradeCount,
            publicTradeCount: overview.publicTradeCount,
            winRate: overview.winRate,
            profitFactor: overview.profitFactor,
            payoutTotal: 0
        )
        XCTAssertTrue(stats.hasLoadedHeaderMetrics)
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, "0%")
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, "$0")
        XCTAssertEqual(metrics.first(where: { $0.id == "publicTrades" })?.value, "0")
    }

    func testLoadedStatsFormatWinRateAndProfitFactor() {
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 10,
            followingCount: 3,
            postCount: 2,
            tradeCount: 8,
            publicTradeCount: 8,
            winRate: Decimal(string: "0.625"),
            profitFactor: Decimal(string: "1.85"),
            payoutTotal: Decimal(string: "1200")
        )
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(metrics.first(where: { $0.id == "publicTrades" })?.value, "8")
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, "$1,200")
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, "62.5%")
        XCTAssertEqual(metrics.first(where: { $0.id == "profitFactor" })?.value, "1.9")
    }

    @MainActor
    func testPartialStubCannotOverwriteRicherCachedStats() {
        let cache = DetailPresentationCache()
        let profileID = ProfileID("viewer")
        let rich = ProfileStats(
            profileID: profileID,
            followerCount: 12,
            followingCount: 4,
            postCount: 3,
            tradeCount: 5,
            publicTradeCount: 5,
            winRate: Decimal(string: "0.6"),
            profitFactor: Decimal(string: "2.1"),
            payoutTotal: Decimal(string: "500")
        )
        cache.seed(stats: rich)

        let stub = ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 9,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
        cache.seed(stats: stub)

        let cached = cache.stats(for: profileID)
        XCTAssertEqual(cached?.publicTradeCount, 5)
        XCTAssertEqual(cached?.winRate, Decimal(string: "0.6"))
        XCTAssertEqual(cached?.followingCount, 9)
    }
}
