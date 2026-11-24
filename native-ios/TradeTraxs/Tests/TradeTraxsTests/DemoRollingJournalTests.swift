import XCTest
@testable import TradeTraxs

final class DemoRollingJournalTests: XCTestCase {
    override func tearDown() {
        DemoRollingJournal.shared.invalidateCache()
        DemoSnapshotStore.shared.clearMemory()
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
        super.tearDown()
    }

    func testRollingJournalSpansTwelveMonthsWithoutFutureTrades() throws {
        let now = Date()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)
        XCTAssertGreaterThan(trades.count, 200)

        let calendar = TradingReportPeriods.eastern
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .month, value: -DemoCanonicalDataset.rollingJournalHistoryMonths, to: today) else {
            XCTFail("history start")
            return
        }
        let minEntry = trades.map(\.entryAt).min()!
        XCTAssertGreaterThanOrEqual(minEntry, calendar.startOfDay(for: earliest))
        XCTAssertTrue(trades.allSatisfy { $0.entryAt <= now })
        XCTAssertTrue(trades.allSatisfy { ($0.exitAt ?? $0.entryAt) <= now })
    }

    func testCurrentCalendarWeekIncludesTradesThroughToday() {
        let now = Date()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)
        let bounds = TradingReportPeriods.bounds(for: .weeklyThis, now: now)
        let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
        let endKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.end)
        let weekTrades = trades.filter { trade in
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            return key >= startKey && key <= endKey
        }
        XCTAssertGreaterThan(weekTrades.count, 0)
    }

    func testOneYearScopeSupportsPremiumDashboardCharts() {
        let now = Date()
        DemoRollingJournal.shared.invalidateCache()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)

        let scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .oneYear,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false,
            linkedAccountModes: DemoCanonicalDataset.accountModes()
        )
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let summary = DashboardChartMetrics.compute(from: inputs, scope: scope, payoutTotal: 0, now: now)
        XCTAssertGreaterThan(summary.tradeCount, 80, "1Y scope should include a rich sample")
        XCTAssertFalse(summary.holdTimeHistogram.isEmpty)
        XCTAssertNotEqual(summary.holdTime.first(where: { $0.label == "Avg Winner" })?.value, "–")
        XCTAssertGreaterThanOrEqual(summary.rrTargetAnalysis.pairedCount, 5)
        XCTAssertFalse(summary.drawdownSeries.isEmpty)
        XCTAssertNotNil(summary.averageMaxRrReached)
        let metrics = TradingReportGenerator.metrics(for: trades)
        XCTAssertNotNil(metrics.bestDayLabel)
        XCTAssertNotNil(metrics.worstDayLabel)
        XCTAssertNotNil(metrics.bestSessionLabel)
        XCTAssertNotNil(metrics.worstSessionLabel)
        XCTAssertNotNil(metrics.profitFactor)
    }

    func testLastSevenDaysSupportsScopedReportExtremes() {
        let now = Date()
        DemoRollingJournal.shared.invalidateCache()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)

        let scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .sevenDays,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false,
            linkedAccountModes: DemoCanonicalDataset.accountModes()
        )
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let scoped = DashboardChartMetrics.filteredTrades(from: inputs, scope: scope, now: now)
        XCTAssertGreaterThan(scoped.count, 8, "7D scope should include a dense sample")
        let metrics = TradingReportGenerator.metrics(for: scoped)
        XCTAssertNotNil(metrics.profitFactor)
        XCTAssertNotNil(metrics.bestDayLabel)
        XCTAssertNotNil(metrics.worstDayLabel)
        XCTAssertNotNil(metrics.bestSessionLabel)
        XCTAssertNotNil(metrics.worstSessionLabel)
    }

    func testLastNinetyDaysSupportsPremiumDashboardCharts() {
        let now = Date()
        DemoRollingJournal.shared.invalidateCache()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)

        let scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .ninetyDays,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false,
            linkedAccountModes: DemoCanonicalDataset.accountModes()
        )
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let summary = DashboardChartMetrics.compute(from: inputs, scope: scope, payoutTotal: 0, now: now)
        XCTAssertGreaterThan(summary.tradeCount, 60, "90D scope should include a rich sample")
        XCTAssertFalse(summary.holdTimeHistogram.isEmpty)
        XCTAssertNotNil(summary.profitFactor)
        XCTAssertFalse(summary.drawdownSeries.isEmpty)
        let scoped = DashboardChartMetrics.filteredTrades(from: inputs, scope: scope, now: now)
        let metrics = TradingReportGenerator.metrics(for: scoped)
        XCTAssertNotNil(metrics.bestDayLabel)
        XCTAssertNotNil(metrics.worstDayLabel)
    }

    func testLastThirtyDaysSupportsPremiumDashboardCharts() {
        let now = Date()
        DemoRollingJournal.shared.invalidateCache()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)

        let scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .thirtyDays,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false,
            linkedAccountModes: DemoCanonicalDataset.accountModes()
        )
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let summary = DashboardChartMetrics.compute(from: inputs, scope: scope, payoutTotal: 0, now: now)
        XCTAssertGreaterThan(summary.tradeCount, 30, "30D scope should include a rich sample")
        XCTAssertFalse(summary.holdTimeHistogram.isEmpty)
        XCTAssertNotEqual(summary.holdTime.first(where: { $0.label == "Avg Winner" })?.value, "–")
        XCTAssertNotEqual(summary.holdTime.first(where: { $0.label == "Avg Loser" })?.value, "–")
        XCTAssertGreaterThanOrEqual(summary.holdExtremes.count, 2)
        XCTAssertNotNil(summary.hourHighlights)
        XCTAssertGreaterThanOrEqual(summary.rrTargetAnalysis.pairedCount, 5)
        XCTAssertNotNil(summary.rrTargetAnalysis.avgTargetAttainmentRatio)
    }

    func testLastThirtyDaysHasTwoQualifyingSetups() {
        let now = Date()
        let trades = DemoRollingJournal.shared.trades(now: now, forceRebuild: true)
        let calendar = TradingReportPeriods.eastern
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let recent = trades.filter { $0.entryAt >= start && $0.entryAt <= now }
        var bySetup: [String: Int] = [:]
        for trade in recent {
            guard let strategy = trade.strategy, !strategy.isEmpty, trade.realizedPnL != nil else { continue }
            bySetup[strategy, default: 0] += 1
        }
        let qualified = bySetup.filter { $0.value >= 5 }
        XCTAssertGreaterThanOrEqual(qualified.count, 2, bySetup.description)
    }

    func testPreviewBypassesInstalledSnapshotJournal() throws {
        var snapshot = DemoSnapshot.captureBundled(version: 99)
        snapshot.trades = []
        DemoSnapshotStore.shared.install(snapshot)
        defer { DemoSnapshotStore.shared.clearMemory() }

        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = true
        let trades = DemoCanonicalDataset.trades()
        XCTAssertFalse(trades.isEmpty)
        XCTAssertTrue(trades.contains { $0.id.rawValue.contains("demo-trade-20") || $0.id.rawValue.hasPrefix("demo-trade-") })
    }

    func testWeeklyTradingReportHasTradesOnSimulatedMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingReportPeriods.eastern.timeZone
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        comps.hour = 10
        comps.minute = 30
        let monday = try XCTUnwrap(calendar.date(from: comps))

        let trades = DemoRollingJournal.shared.trades(now: monday, forceRebuild: true)
        let report = TradingReportGenerator.generate(trades: trades, periodKey: .weeklyThis, now: monday)
        XCTAssertGreaterThan(report.metrics.tradesTaken, 0, report.executiveSummary)
    }
}