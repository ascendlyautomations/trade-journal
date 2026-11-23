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

    func testParseHistoricalBundleMapsOverview() throws {
        let json = """
        {
          "seriesDays": 30,
          "meta": { "notes": ["Content only"], "isContentActivityNotSessions": true, "maxSeriesDays": 365 },
          "overview": {
            "engagedDau": 3,
            "engagedWau": 8,
            "engagedMau": 12,
            "activeTradersDau": 2,
            "activeCreatorsDau": 1,
            "activeMessengersDau": 4,
            "newSignupsInPeriod": 5,
            "accountsCreatedInPeriod": 2
          },
          "growth": { "signupsPerDay": [], "accountsCreatedPerDay": [] },
          "trading": {
            "tradesLoggedPerDay": [],
            "organicTradesLoggedPerDay": [],
            "bulkImportTradesPerDay": [],
            "tradesByExecutionDatePerDay": [],
            "activeTradersPerDay": [],
            "returningTradersPerDay": [],
            "importQuality": {
              "manualEntered": 1,
              "unsetImportSource": 0,
              "csv": 0,
              "broker": 0,
              "other": 0,
              "bulkInitialImportRows": 0,
              "organicTradesLogged": 1,
              "tradeDateBeforeCreatedDayRows": 0,
              "nullTradeDateRows": 0
            }
          },
          "social": {
            "postsPerDay": [],
            "profilePostsPerDay": [],
            "reelsPerDay": [],
            "commentsPerDay": [],
            "likesPerDay": [],
            "followsPerDay": [],
            "messagesPerDay": [],
            "activeCreatorsPerDay": [],
            "activeMessengersPerDay": []
          },
          "engagement": {
            "engagedUsersPerDay": [],
            "returningEngagedUsersPerDay": [],
            "returningCreatorsPerDay": []
          },
          "retention": {
            "d1Rate": 10,
            "d7Rate": null,
            "d30Rate": null,
            "cohortSignupsTotal": 20,
            "d1MatureCohortSize": 5,
            "d7MatureCohortSize": 0,
            "d30MatureCohortSize": 0,
            "insufficientData": false,
            "definition": "content action"
          }
        }
        """.data(using: .utf8)!
        let bundle = try AdminHistoricalEngagementParsing.parseBundle(from: json)
        XCTAssertEqual(bundle.overview.engagedDau, 3)
        XCTAssertEqual(bundle.retentionD1MatureCohortSize, 5)
    }

    func testParseProductBundleMapsOverview() throws {
        let json = """
        {
          "seriesDays": 7,
          "meta": {
            "productTrackingStartDate": "2026-11-22",
            "productEngagementAvailable": true,
            "retentionMetricsAvailable": true,
            "previewFunnelAvailable": true,
            "notes": ["Test note"]
          },
          "overview": {
            "totalUsers": 100,
            "newSignupsToday": 2,
            "productDau": 10,
            "productWau": 20,
            "productMau": 30,
            "dauMauRatio": 0.33
          },
          "growth": { "signupsPerDay": [], "productActiveUsersPerDay": [] },
          "retention": {
            "d1Rate": 50,
            "d7Rate": 40,
            "d30Rate": null,
            "returningUsersPerDay": [],
            "cohortSampleSignups": 5,
            "d1MatureCohortSize": 3,
            "d7MatureCohortSize": 0,
            "d30MatureCohortSize": 0,
            "insufficientData": false
          },
            "trading": {
            "tradesCreatedPerDay": [],
            "activeTradersPerDay": [],
            "tradesPerActiveTraderLatestDay": 1.5,
            "importTotalsInPeriod": {
              "manualEntered": 1,
              "unsetImportSource": 2,
              "csv": 2,
              "broker": 3,
              "other": 0
            }
          },
          "social": {
            "profileViewsPerDay": [],
            "uniqueProfileViewersPerDay": [],
            "postsPerDay": [],
            "featureEngagementPerDay": []
          },
          "features": { "topFeatures": [] },
          "traxsProPreview": {
            "available": true,
            "startsPerDay": [],
            "exitsPerDay": [],
            "upgradeTapsPerDay": [],
            "funnelTotals": { "starts": 1, "exits": 1, "upgradeTaps": 0, "startToUpgradeRate": null }
          }
        }
        """.data(using: .utf8)!
        let bundle = try AdminProductAnalyticsParsing.parseBundle(from: json)
        XCTAssertEqual(bundle.overview.productDau, 10)
        XCTAssertEqual(bundle.meta.notes.first, "Test note")
        XCTAssertNil(bundle.retentionD30Rate)
    }
}

private final class MockAdminUsageAnalyticsRepository: AdminUsageAnalyticsRepository, @unchecked Sendable {
    var bundles: [Int: AdminUsageAnalyticsBundle] = [:]
    var productBundles: [Int: AdminProductAnalyticsBundle] = [:]
    var fetchCount = 0

    func fetchBundle(seriesDays: Int) async throws -> AdminUsageAnalyticsBundle {
        fetchCount += 1
        if let bundle = bundles[seriesDays] { return bundle }
        throw AdminUsageAnalyticsError.invalidResponse
    }

    func fetchProductBundle(seriesDays: Int) async throws -> AdminProductAnalyticsBundle {
        if let bundle = productBundles[seriesDays] { return bundle }
        throw AdminUsageAnalyticsError.invalidResponse
    }

    func fetchHistoricalBundle(query: AdminHistoricalEngagementQuery) async throws -> AdminHistoricalEngagementBundle {
        throw AdminUsageAnalyticsError.invalidResponse
    }

    func fetchLifecycleBundle(query: AdminLifecycleAnalyticsQuery) async throws -> AdminLifecycleAnalyticsBundle {
        _ = query
        throw AdminUsageAnalyticsError.invalidResponse
    }
}
