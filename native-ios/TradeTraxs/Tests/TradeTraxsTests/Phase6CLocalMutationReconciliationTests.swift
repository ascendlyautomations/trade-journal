import XCTest
@testable import TradeTraxs

final class Phase6CLocalMutationReconciliationTests: XCTestCase {
    private var viewer: ProfileID { ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }

    func testUpdateScopeIncludesBothDaysAndAccounts() {
        let old = makeTrade(day: "2025-09-10", account: "aaaa", mode: .sim)
        var updated = old
        updated.entryAt = makeDate(day: "2025-09-11")
        updated.exitAt = updated.entryAt
        updated.accountID = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

        let scope = AnalyticsLocalMutationScopeBuilder.update(old: old, new: updated)
        XCTAssertEqual(scope.oldCalendarDay, "2025-09-10")
        XCTAssertEqual(scope.newCalendarDay, "2025-09-11")
        XCTAssertEqual(scope.calendarRanges.first?.startDate, "2025-09-10")
        XCTAssertEqual(scope.calendarRanges.first?.endDate, "2025-09-11")
        XCTAssertEqual(Set(scope.accountChartAccountIDs).count, 2)
    }

    func testDeleteScopeCapturesOldBucket() {
        let trade = makeTrade(day: "2025-08-31", account: "aaaa", mode: .sim)
        let scope = AnalyticsLocalMutationScopeBuilder.delete(old: trade)
        XCTAssertEqual(scope.oldCalendarDay, "2025-08-31")
        XCTAssertEqual(scope.calendarRanges.first?.startDate, "2025-08-31")
    }

    func testBulkScopeIsSingleIntentShape() {
        let scope = AnalyticsLocalMutationScopeBuilder.bulkImport(
            viewerID: viewer,
            visibleMonth: ("2025-09-01", "2025-09-30")
        )
        XCTAssertTrue(scope.requestsDashboardBootstrap)
        XCTAssertEqual(scope.calendarRanges.count, 1)
    }

    private func makeTrade(day: String, account: String, mode: TradeMode) -> Trade {
        let date = makeDate(day: day)
        return Trade(
            id: TradeID(UUID().uuidString),
            ownerProfileID: viewer,
            accountID: TradingAccountID(account),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: mode,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: date,
            exitAt: date,
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeDate(day: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsCalendarDay.timeZone
        let parts = day.split(separator: "-").map(String.init)
        return calendar.date(from: DateComponents(
            year: Int(parts[0]),
            month: Int(parts[1]),
            day: Int(parts[2])
        )) ?? Date()
    }
}
