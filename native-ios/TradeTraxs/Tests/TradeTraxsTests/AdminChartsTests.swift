import XCTest
@testable import TradeTraxs

final class AdminChartsTests: XCTestCase {
    func testNormalizeSeriesFillsZeroDays() {
        let filled = AdminUsageAnalyticsParsing.normalizeSeries([], seriesDays: 7)
        XCTAssertEqual(filled.count, 7)
        XCTAssertTrue(filled.allSatisfy { $0.count == 0 })
    }

    func testParseBundleMapsSeries() throws {
        let json = """
        {
          "totalUsers": 10,
          "newUsersToday": 1,
          "newUsersWeek": 2,
          "dailyActiveUsers": 3,
          "weeklyActiveUsers": 4,
          "tradesToday": 1,
          "tradesWeek": 2,
          "postsToday": 1,
          "postsWeek": 2,
          "totalTrades": 100,
          "totalPosts": 50,
          "seriesDays": 2,
          "series": {
            "usersPerDay": [{"day":"2026-09-28","count":1}],
            "activeUsersPerDay": [{"day":"2026-09-28","count":2}],
            "tradesPerDay": [{"day":"2026-09-28","count":3}],
            "postsPerDay": [{"day":"2026-09-28","count":4}],
            "reelsPerDay": [],
            "commentsPerDay": [],
            "likesPerDay": [],
            "followsPerDay": []
          }
        }
        """.data(using: .utf8)!
        let bundle = try AdminUsageAnalyticsParsing.parseBundle(from: json)
        XCTAssertEqual(bundle.series.tradesPerDay.first?.count, 3)
        XCTAssertEqual(bundle.dailyActiveUsers, 3)
    }

    func testAveragesAndTotals() {
        let points = [
            AdminUsageDailyCount(day: "2026-09-01", count: 2),
            AdminUsageDailyCount(day: "2026-09-02", count: 4),
        ]
        XCTAssertEqual(AdminUsageAnalyticsMath.totalCount(points), 6)
        XCTAssertEqual(AdminUsageAnalyticsMath.averagePerDay(points), 3)
    }

    func testChartsRangeDefaultsTo30Days() {
        XCTAssertEqual(AdminChartsRange.days30.rawValue, 30)
    }

    @MainActor
    func testViewModelDoesNotAutoRetryFailedRange() async {
        let repo = MockAdminUsageAnalyticsRepository()
        repo.bundles[30] = nil
        let vm = AdminChartsViewModel(repository: repo)
        vm.selectedRange = .days30
        await vm.load()
        XCTAssertEqual(repo.fetchCount, 1)
        XCTAssertNotNil(vm.errorMessage)
        await vm.load()
        XCTAssertEqual(repo.fetchCount, 1, "Deterministic failure should not auto-retry")
        await vm.load(force: true)
        XCTAssertEqual(repo.fetchCount, 2, "Try Again should refetch")
    }

    @MainActor
    func testViewModelCachesRangeResults() async {
        let repo = MockAdminUsageAnalyticsRepository()
        repo.bundles[30] = sampleBundle(days: 30)
        let vm = AdminChartsViewModel(repository: repo)
        vm.selectedRange = .days30
        await vm.load()
        XCTAssertEqual(repo.fetchCount, 1)
        await vm.load()
        XCTAssertEqual(repo.fetchCount, 1)
        vm.selectedRange = .days7
        repo.bundles[7] = sampleBundle(days: 7)
        await vm.onRangeChanged()
        XCTAssertEqual(repo.fetchCount, 2)
    }

    func testAdminChartsRouteIsRealScreen() {
        XCTAssertEqual(String(describing: AdminChartsView.self), "AdminChartsView")
    }

    func testParseMalformedBundleThrows() {
        XCTAssertThrowsError(try AdminUsageAnalyticsParsing.parseBundle(from: Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AdminUsageAnalyticsError, .invalidResponse)
        }
    }

    func testChartsRangeValues() {
        XCTAssertEqual(AdminChartsRange.allCases.map(\.rawValue), [7, 30, 90, 365])
    }

    func testLatestDayCountMapsDAUSummary() {
        let points = [
            AdminUsageDailyCount(day: "2026-09-01", count: 1),
            AdminUsageDailyCount(day: "2026-09-02", count: 9),
        ]
        XCTAssertEqual(AdminUsageAnalyticsMath.latestDayCount(points), 9)
    }

    private func sampleBundle(days: Int) -> AdminUsageAnalyticsBundle {
        AdminUsageAnalyticsBundle(
            totalUsers: 1,
            newUsersToday: 0,
            newUsersWeek: 0,
            dailyActiveUsers: 0,
            weeklyActiveUsers: 0,
            tradesToday: 0,
            tradesWeek: 0,
            postsToday: 0,
            postsWeek: 0,
            totalTrades: 0,
            totalPosts: 0,
            seriesDays: days,
            series: AdminUsageAnalyticsSeries(
                usersPerDay: [],
                activeUsersPerDay: [],
                tradesPerDay: [],
                postsPerDay: [],
                reelsPerDay: [],
                commentsPerDay: [],
                likesPerDay: [],
                followsPerDay: []
            )
        )
    }
}

private final class MockAdminUsageAnalyticsRepository: AdminUsageAnalyticsRepository, @unchecked Sendable {
    var bundles: [Int: AdminUsageAnalyticsBundle] = [:]
    var fetchCount = 0

    func fetchBundle(seriesDays: Int) async throws -> AdminUsageAnalyticsBundle {
        fetchCount += 1
        if let bundle = bundles[seriesDays] { return bundle }
        throw AdminUsageAnalyticsError.invalidResponse
    }
}
