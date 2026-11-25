import XCTest
@testable import TradeTraxs

@MainActor
final class ReportsExperienceTests: XCTestCase {
    func testGeneratorMatchesWebPeriodKeys() throws {
        let profile = ProfileID("dev.reports.user")
        let trades = ProfileTradeFixtures.samples(owner: profile)
        let reports = TradingReportGenerator.generateAll(trades: trades)

        XCTAssertEqual(Set(reports.keys), Set(TradingReportPeriodKey.allCases))
        for key in TradingReportPeriodKey.allCases {
            let report = try XCTUnwrap(reports[key])
            XCTAssertEqual(report.periodKey, key)
            XCTAssertEqual(report.summarySource, "deterministic")
            XCTAssertFalse(report.title.isEmpty)
            XCTAssertFalse(report.executiveSummary.isEmpty)
        }
    }

    func testWeeklySessionMetricsUseEntryTimeMacroBuckets() throws {
        let eastern = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern

        func sessionTrade(id: String, hour: Int, minute: Int, pnl: Decimal) -> Trade {
            let entry = calendar.date(
                from: DateComponents(
                    timeZone: eastern,
                    year: 2026,
                    month: 11,
                    day: 10,
                    hour: hour,
                    minute: minute
                )
            )!
            return Trade(
                id: TradeID(id),
                ownerProfileID: ProfileID("dev.reports.user"),
                accountID: nil,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 100,
                exitPrice: 101,
                entryAt: entry,
                exitAt: entry.addingTimeInterval(3600),
                realizedPnL: Money(amount: pnl),
                riskReward: 1,
                points: 0,
                sessionLabel: nil,
                visibility: .private,
                createdAt: entry,
                updatedAt: entry
            )
        }

        let trades = [
            sessionTrade(id: "l1", hour: 5, minute: 30, pnl: 120),
            sessionTrade(id: "l2", hour: 6, minute: 0, pnl: 80),
            sessionTrade(id: "a1", hour: 20, minute: 0, pnl: -40),
            sessionTrade(id: "a2", hour: 21, minute: 0, pnl: -60),
            sessionTrade(id: "n1", hour: 9, minute: 30, pnl: 25),
        ]

        let report = TradingReportGenerator.generate(
            trades: trades,
            week: TradingReportWeekRef(mondayKey: "2026-11-09")
        )

        XCTAssertEqual(report.metrics.bestSessionLabel, "London")
        XCTAssertEqual(report.metrics.bestSessionPnl ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(report.metrics.worstSessionLabel, "Asia")
        XCTAssertEqual(report.metrics.worstSessionPnl ?? 0, -100, accuracy: 0.01)
    }

    func testTradingReportDetailBlockOrder() {
        let metrics = TradingReportMetrics(
            netPnl: 100,
            winRate: 50,
            knownResultCount: 2,
            averageRr: 1,
            averageReachedRr: 1.5,
            profitFactor: 1.2,
            tradesTaken: 2,
            bestDayLabel: nil,
            bestDayPnl: nil,
            worstDayLabel: nil,
            worstDayPnl: nil,
            bestSessionLabel: "London",
            bestSessionPnl: 80,
            worstSessionLabel: nil,
            worstSessionPnl: nil,
            mostTradedSymbol: "ES",
            averageHoldTimeSeconds: 60
        )
        let report = TradingReport(
            periodKey: .weeklyLast,
            kind: .weekly,
            title: "Weekly Trading Report",
            dateRangeLabel: "Nov 3–9, 2026",
            periodStartIso: "",
            periodEndIso: "",
            generatedAt: 0,
            executiveSummary: "Summary",
            metrics: metrics,
            strengths: ["Strength"],
            opportunities: ["Weakness"],
            recommendations: [],
            bestTradeId: nil,
            keyTakeaway: "",
            summarySource: "deterministic"
        )
        let blocks = TradingReportDetailBlock.blocks(from: report)
        XCTAssertEqual(blocks.map(\.id), ["summary", "strengthsAndWeaknesses", "metrics"])

        var full = report
        full.recommendations = ["Do more of X"]
        full.keyTakeaway = "Keep risk steady."
        let ordered = TradingReportDetailBlock.blocks(from: full)
        XCTAssertEqual(
            ordered.map(\.id),
            ["summary", "strengthsAndWeaknesses", "recommendations", "keyTakeaway", "metrics"]
        )
    }

    func testHistoricalWeekOpensTheStoredMonday() throws {
        let later = ISO8601DateFormatter().date(from: "2026-11-21T17:00:00Z")!
        let ref = TradingReportWeekRef.parse(reportID: ReportID("week:2026-11-09"))
        XCTAssertEqual(ref?.mondayKey, "2026-11-09")
        XCTAssertNil(TradingReportWeekRef.parse(reportID: ReportID("week:2026-11-10")))
        XCTAssertNil(TradingReportWeekRef.parse(reportID: ReportID("weekly_last")))

        let bounds = TradingReportPeriods.bounds(forWeekStarting: "2026-11-09", now: later)
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds?.start ?? later),
            "2026-11-09"
        )
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds?.end ?? later),
            "2026-11-15"
        )

        let saturday = ISO8601DateFormatter().date(from: "2026-11-14T17:00:00Z")!
        let inProgress = TradingReportPeriods.bounds(forWeekStarting: "2026-11-09", now: saturday)
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: inProgress?.end ?? saturday),
            "2026-11-14"
        )

        let content = """
        {"title":"Your Weekly Trading Report is Ready","href":"/dashboard?report=weekly_last","periodKey":"weekly_last","periodId":"week:2026-11-09","kind":"weekly"}
        """
        let envelope: [String: Any] = [
            "id": "n-week",
            "type": "trading_report",
            "content": content,
            "created_at": "2026-11-14T17:00:00Z",
            "read": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let dto = try JSONDecoder().decode(NotificationDTO.Item.self, from: data)
        let mapped = DefaultNotificationRepository.mapNotification(dto)
        XCTAssertEqual(mapped?.reportID?.rawValue, "week:2026-11-09")
    }

    func testPeriodBoundsMatchWebCalendarWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday — matches JS Date.getDay() week math
        let now = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: 12
        ))!

        let weeklyThis = TradingReportPeriods.bounds(for: .weeklyThis, now: now, calendar: calendar)
        let weeklyLast = TradingReportPeriods.bounds(for: .weeklyLast, now: now, calendar: calendar)
        let monthlyThis = TradingReportPeriods.bounds(for: .monthlyThis, now: now, calendar: calendar)
        let monthlyLast = TradingReportPeriods.bounds(for: .monthlyLast, now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents([.day], from: weeklyLast.start, to: weeklyThis.start).day ?? -1,
            7
        )
        XCTAssertLessThanOrEqual(weeklyThis.start, weeklyThis.end)
        XCTAssertLessThan(weeklyLast.end, weeklyThis.start)
        XCTAssertEqual(calendar.component(.day, from: monthlyThis.start), 1)
        XCTAssertEqual(
            calendar.dateComponents([.month], from: monthlyLast.start, to: monthlyThis.start).month ?? -1,
            1
        )
        XCTAssertLessThan(monthlyLast.end, monthlyThis.start)
    }

    func testBootstrapLoadsFourWebPeriodsWithoutAI() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let repository = StubTradingReportRepository()
        let psychologyRepository = StubPsychologyReportRepository()
        let viewModel = ReportsScreenViewModel(
            tradingReports: repository,
            psychologyReports: psychologyRepository,
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.cards.count, 4)
        XCTAssertEqual(viewModel.psychologyCards.count, PsychologyReportTemplate.allCases.count)
        XCTAssertEqual(
            viewModel.cards.map(\.periodKey),
            TradingReportPeriodKey.allCases
        )
        XCTAssertTrue(viewModel.cards.allSatisfy { $0.availability == .ready })
        let ensureCalls = await repository.ensureCallCount()
        XCTAssertEqual(ensureCalls, 1)
    }

    func testViewReportPushesDetailWithoutRegeneration() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let repository = StubTradingReportRepository()
        let viewModel = ReportsScreenViewModel(
            tradingReports: repository,
            psychologyReports: StubPsychologyReportRepository(),
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()
        let before = await repository.reportCallCount()
        let card = try XCTUnwrap(viewModel.cards.first)
        viewModel.primaryAction(for: card)
        try await Task.sleep(nanoseconds: 200_000_000)

        let after = await repository.reportCallCount()
        XCTAssertEqual(after, before)
        XCTAssertEqual(store.paths.home.last, .report(card.periodKey.reportID))
    }

    func testCustomRangeRefRoundTrip() {
        let calendar = TradingReportPeriods.eastern
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: start,
            end: end,
            calendar: calendar
        )
        let ref = TradingReportCustomRangeRef.from(interval: interval)
        let parsed = TradingReportCustomRangeRef.parse(reportID: ref.reportID)
        XCTAssertEqual(parsed, ref)
    }

    func testCustomRangeValidationRejectsFutureEnd() {
        let calendar = TradingReportPeriods.eastern
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertNotNil(
            TradingReportCustomRangeSupport.validationMessage(
                start: Date(),
                end: tomorrow,
                now: Date(),
                calendar: calendar
            )
        )
    }

    func testCustomReportUsesOnlyTradesInRange() {
        let eastern = TradingReportPeriods.eastern
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern.timeZone
        let owner = ProfileID("dev.custom.report")
        let inRange = makeCustomRangeTrade(
            id: "in",
            owner: owner,
            year: 2026,
            month: 3,
            day: 10,
            pnl: 100,
            calendar: calendar
        )
        let outRange = makeCustomRangeTrade(
            id: "out",
            owner: owner,
            year: 2026,
            month: 4,
            day: 2,
            pnl: 500,
            calendar: calendar
        )
        let start = eastern.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = eastern.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 23, minute: 59))!
        let interval = DateInterval(start: start, end: end)
        let report = TradingReportGenerator.generateCustomRange(
            trades: [inRange, outRange],
            interval: interval,
            filters: TradingReportFilters()
        )
        XCTAssertEqual(report.kind, .custom)
        XCTAssertEqual(report.metrics.tradesTaken, 1)
        XCTAssertEqual(report.metrics.netPnl, 100, accuracy: 0.01)
    }

    func testCatalogListVisibilityShowsTwoUntilExpanded() {
        let items = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(
            ReportsCatalogListVisibility.visibleItems(from: items, listExpanded: false, compactCount: 2),
            ["a", "b"]
        )
        XCTAssertEqual(
            ReportsCatalogListVisibility.visibleItems(from: items, listExpanded: true, compactCount: 2),
            items
        )
        XCTAssertEqual(
            ReportsCatalogListVisibility.visibleItems(from: ["only"], listExpanded: false, compactCount: 2),
            ["only"]
        )
    }

    func testReportCardTrailingTitlesUseCompactChevrons() {
        XCTAssertEqual(ReportCard.trailingTitle(for: "View Report", isGenerating: false), "View ›")
        XCTAssertEqual(ReportCard.trailingTitle(for: "Generate", isGenerating: false), "Generate ›")
        XCTAssertEqual(ReportCard.trailingTitle(for: "Choose Period", isGenerating: false), "Choose Period ›")
        XCTAssertEqual(ReportCard.trailingTitle(for: "View Report", isGenerating: true), "Generating…")
    }

    func testOpenPsychologyReportUsesLatestPeriodWithoutOpeningPicker() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = ReportsScreenViewModel(
            tradingReports: StubTradingReportRepository(),
            psychologyReports: StubPsychologyReportRepository(),
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()
        let weekly = try XCTUnwrap(
            viewModel.psychologyCards.first { $0.template == .weekly }
        )
        let ref = try XCTUnwrap(weekly.periodRef)

        viewModel.openPsychologyReport(for: weekly)

        XCTAssertFalse(viewModel.showsPeriodPicker)
        XCTAssertEqual(store.paths.home.last, .report(ref.reportID))
    }

    func testShowPsychologyPeriodPickerDoesNotNavigate() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = ReportsScreenViewModel(
            tradingReports: StubTradingReportRepository(),
            psychologyReports: StubPsychologyReportRepository(),
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()
        let weekly = try XCTUnwrap(
            viewModel.psychologyCards.first { $0.template == .weekly }
        )
        let pathCountBefore = store.paths.home.count

        viewModel.showPsychologyPeriodPicker(for: weekly)

        XCTAssertTrue(viewModel.showsPeriodPicker)
        XCTAssertEqual(store.paths.home.count, pathCountBefore)
    }

    func testDetailRendersDynamicBlocks() async {
        let viewModel = makeDetailViewModel(periodKey: .weeklyLast)
        await viewModel.bootstrapIfNeeded()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.blocks.isEmpty)
        XCTAssertTrue(viewModel.blocks.contains { if case .summary = $0 { return true }; return false })
        XCTAssertTrue(viewModel.blocks.contains { if case .metrics = $0 { return true }; return false })
    }

    func testBestTradeResolvesFromCacheAndOpensTradeDetail() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let cache = DetailPresentationCache()
        let tradesRepo = StubReportsTradeRepository()
        let sample = try XCTUnwrap(
            ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.user")).first
        )
        cache.seed(sample)

        let reportsRepo = StubTradingReportRepository(
            forcedBestTradeID: sample.id.rawValue
        )
        let viewModel = ReportDetailViewModel(
            periodKey: .weeklyThis,
            tradingReports: reportsRepo,
            trades: tradesRepo,
            session: StubReportsSession(userID: "dev.reports.user"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()

        guard case .available(let trade) = viewModel.bestTrade else {
            return XCTFail("Expected available best trade, got \(String(describing: viewModel.bestTrade))")
        }
        XCTAssertEqual(trade.id, sample.id)
        XCTAssertEqual(tradesRepo.fetchCount, 0) // cache hit

        viewModel.openBestTrade()
        XCTAssertEqual(store.paths.home.last, .tradeDetail(sample.id))
    }

    func testBestTradeUnavailableWhenMissing() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let reportsRepo = StubTradingReportRepository(
            forcedBestTradeID: "missing-trade-id"
        )
        let tradesRepo = StubReportsTradeRepository(shouldFail: true)
        let viewModel = ReportDetailViewModel(
            periodKey: .weeklyThis,
            tradingReports: reportsRepo,
            trades: tradesRepo,
            session: StubReportsSession(userID: "dev.reports.user"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )

        await viewModel.bootstrapIfNeeded()
        XCTAssertEqual(viewModel.bestTrade, .unavailable)
    }

    func testBestTradeInPreviewRejectsNonCanonicalTrade() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let cache = DetailPresentationCache()
        let userTrade = try XCTUnwrap(
            ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.user")).first
        )
        cache.seed(userTrade)
        let reportsRepo = StubTradingReportRepository(forcedBestTradeID: userTrade.id.rawValue)
        let viewModel = ReportDetailViewModel(
            periodKey: .weeklyThis,
            tradingReports: reportsRepo,
            trades: StubReportsTradeRepository(shouldFail: true),
            session: StubReportsSession(userID: "dev.reports.user"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        defer { TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache) }

        await viewModel.bootstrapIfNeeded()
        XCTAssertEqual(viewModel.bestTrade, .unavailable)
        viewModel.openBestTrade()
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    func testBestTradeInPreviewOpensCanonicalSample() async throws {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let cache = DetailPresentationCache()
        let sample = try XCTUnwrap(DemoCanonicalDataset.trades().first)
        let reportsRepo = StubTradingReportRepository(forcedBestTradeID: sample.id.rawValue)
        let viewModel = ReportDetailViewModel(
            periodKey: .weeklyThis,
            tradingReports: reportsRepo,
            trades: StubReportsTradeRepository(shouldFail: true),
            session: StubReportsSession(userID: "dev.reports.user"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        defer { TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache) }

        await viewModel.bootstrapIfNeeded()
        guard case .available(let trade) = viewModel.bestTrade else {
            return XCTFail("Expected canonical best trade")
        }
        XCTAssertEqual(trade.id, sample.id)
        viewModel.openBestTrade()
        XCTAssertEqual(store.paths.home.last, .tradeDetail(sample.id))
    }

    func testReportsNavigationOpensCatalog() {
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)

        ReportsNavigation.openCatalog(using: coordinator)
        XCTAssertEqual(navigationStore.paths.home.last, .reports)
    }

    func testYearBoundsUseJanuaryThroughTodayForCurrentYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12))!
        let bounds = TradingReportPeriods.yearBounds(year: 2026, now: now, calendar: calendar)

        XCTAssertEqual(calendar.component(.month, from: bounds.start), 1)
        XCTAssertEqual(calendar.component(.day, from: bounds.start), 1)
        XCTAssertEqual(calendar.component(.month, from: bounds.end), 9)
        XCTAssertEqual(calendar.component(.day, from: bounds.end), 4)
    }

    func testAvailableYearsOnlyIncludeYearsWithTrades() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let profile = ProfileID("dev.reports.user")
        let trades = ProfileTradeFixtures.samples(owner: profile)
        let years = TradingYearlyReportGenerator.availableYears(from: trades, calendar: calendar)
        XCTAssertFalse(years.isEmpty)
        XCTAssertEqual(years, years.sorted(by: >))
    }

    func testYearlyReportMarksFutureMonthsAsUpcoming() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12))!
        let profile = ProfileID("dev.reports.user")
        let trades = ProfileTradeFixtures.samples(owner: profile)
        let report = TradingYearlyReportGenerator.generate(
            year: 2026,
            trades: trades,
            filters: TradingReportFilters(),
            now: now,
            calendar: calendar
        )

        let upcoming = report.monthRows.filter {
            if case .upcoming = $0.availability { return true }
            return false
        }
        XCTAssertEqual(upcoming.map(\.month), [10, 11, 12])
        XCTAssertTrue(report.monthRows.contains { row in
            row.month == 10 && {
                if case .upcoming = row.availability { return true }
                return false
            }()
        })
    }

    func testYearlyMetricsMatchDashboardChartMetricsForSameScope() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12))!
        let profile = ProfileID("dev.reports.user")
        let trades = ProfileTradeFixtures.samples(owner: profile).filter { $0.mode != .backtest }
        let bounds = TradingReportPeriods.yearBounds(year: 2026, now: now, calendar: calendar)
        let interval = DateInterval(start: bounds.start, end: bounds.end)
        let inputs = trades.map { DashboardChartMetrics.Input(trade: $0, accountType: nil) }
        let summary = DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: .all,
            accountMode: .all,
            interval: interval,
            now: now
        )
        let report = TradingYearlyReportGenerator.generate(
            year: 2026,
            trades: trades,
            filters: TradingReportFilters(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            report.metrics.netPnl,
            NSDecimalNumber(decimal: summary.netPnL).doubleValue,
            accuracy: 0.01
        )
        XCTAssertEqual(report.metrics.tradesTaken, summary.tradeCount)
        XCTAssertEqual(
            report.metrics.maxDrawdown ?? -1,
            NSDecimalNumber(decimal: summary.maxDrawdown).doubleValue,
            accuracy: 0.01
        )
    }

    func testBootstrapIncludesYearlyCard() async throws {
        let viewModel = ReportsScreenViewModel(
            tradingReports: StubTradingReportRepository(),
            psychologyReports: StubPsychologyReportRepository(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        await viewModel.bootstrapIfNeeded()

        XCTAssertNotNil(viewModel.yearlyCard)
        XCTAssertFalse(viewModel.yearlyCard?.availableYears.isEmpty ?? true)
    }

    func testPushRegistrationFlightAllowsALaterUploadOfTheSameToken() async throws {
        let flight = DevicePushRegistrationFlight()
        let counter = PushUploadCounter()
        try await flight.register(token: "abc", previousDeviceToken: nil) {
            counter.value += 1
        }
        try await flight.register(token: "abc", previousDeviceToken: nil) {
            counter.value += 1
        }
        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - Helpers

    private func makeCustomRangeTrade(
        id: String,
        owner: ProfileID,
        year: Int,
        month: Int,
        day: Int,
        pnl: Decimal,
        calendar: Calendar
    ) -> Trade {
        let entry = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
        return Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3600),
            realizedPnL: Money(amount: pnl),
            riskReward: 1,
            points: 0,
            sessionLabel: nil,
            visibility: .private,
            createdAt: entry,
            updatedAt: entry
        )
    }

    private func makeDetailViewModel(
        periodKey: TradingReportPeriodKey
    ) -> ReportDetailViewModel {
        ReportDetailViewModel(
            periodKey: periodKey,
            tradingReports: StubTradingReportRepository(),
            trades: StubReportsTradeRepository(),
            session: StubReportsSession(userID: "dev.reports.user"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
    }
}

// MARK: - Stubs

private actor StubTradingReportRepository: TradingReportRepository {
    private var ensureCalls = 0
    private var reportCalls = 0
    private var snapshot: TradingReportsSnapshot?
    private let forcedBestTradeID: String?

    init(forcedBestTradeID: String? = nil) {
        self.forcedBestTradeID = forcedBestTradeID
    }

    func ensureCallCount() -> Int { ensureCalls }
    func reportCallCount() -> Int { reportCalls }

    func ensureSnapshot(forceNetwork: Bool) async throws -> TradingReportsSnapshot {
        ensureCalls += 1
        if let snapshot { return snapshot }
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        var reports = TradingReportGenerator.generateAll(trades: trades)
        if let forcedBestTradeID {
            for key in TradingReportPeriodKey.allCases {
                guard var report = reports[key] else { continue }
                report.bestTradeId = forcedBestTradeID
                reports[key] = report
            }
        }
        let next = TradingReportsSnapshot(
            reports: reports,
            computedAt: Date().timeIntervalSince1970 * 1000
        )
        snapshot = next
        return next
    }

    func report(
        for periodKey: TradingReportPeriodKey,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        reportCalls += 1
        let snapshot = try await ensureSnapshot(forceNetwork: forceNetwork)
        guard let report = snapshot.report(for: periodKey) else {
            throw AppError.unknown(message: "Missing report")
        }
        return report
    }

    func availableYears(forceNetwork: Bool) async throws -> [Int] {
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        return TradingYearlyReportGenerator.availableYears(from: trades)
    }

    func yearlyReport(
        for year: Int,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingYearlyReport {
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        return TradingYearlyReportGenerator.generate(year: year, trades: trades, filters: filters)
    }

    func monthReport(
        for ref: TradingReportMonthRef,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        return TradingYearlyReportGenerator.generateMonthReport(
            ref: ref,
            trades: trades,
            filters: filters
        )
    }

    func weekReport(
        mondayKey: String,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        _ = forceNetwork
        _ = filters
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        guard let week = TradingReportWeekRef.parse(reportID: ReportID("week:\(mondayKey)")) else {
            throw AppError.unknown(message: "Invalid week")
        }
        return TradingReportGenerator.generate(trades: trades, week: week)
    }

    func customReport(
        for ref: TradingReportCustomRangeRef,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        _ = forceNetwork
        guard let interval = ref.interval else {
            throw AppError.unknown(message: "Invalid custom range")
        }
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        return TradingReportGenerator.generateCustomRange(
            trades: trades,
            interval: interval,
            filters: filters
        )
    }
}

private actor StubPsychologyReportRepository: PsychologyReportRepository {
    private var snapshot: PsychologyReportsSnapshot?

    func ensureSnapshot(forceNetwork: Bool) async throws -> PsychologyReportsSnapshot {
        if let snapshot, !forceNetwork { return snapshot }
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        let next = PsychologyReportGenerator.generateAll(trades: trades, checkIns: [])
        snapshot = next
        await MainActor.run {
            PsychologyReportSessionStore.shared.update(next)
        }
        return next
    }

    func report(for reportID: ReportID, forceNetwork: Bool) async throws -> PsychologyReport {
        let snap = try await ensureSnapshot(forceNetwork: forceNetwork)
        guard let report = snap.report(for: reportID) else {
            throw AppError.unknown(message: "Missing psychology report")
        }
        return report
    }

    func generateReport(
        periodRef: PsychologyReportPeriodRef,
        forceNetwork: Bool
    ) async throws -> PsychologyReport {
        _ = forceNetwork
        let snap = try await ensureSnapshot(forceNetwork: false)
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.stub"))
        return PsychologyReportGenerator.generate(
            periodRef: periodRef,
            trades: trades,
            checkIns: [],
            preferences: nil
        )
    }
}

private struct StubReportsSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { nil } }
}

private final class StubReportsTradeRepository: TradeRepository, @unchecked Sendable {
    private(set) var fetchCount = 0
    var shouldFail = false
    private let samples: [Trade]

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
        self.samples = ProfileTradeFixtures.samples(owner: ProfileID("dev.reports.user"))
    }

    func trade(id: TradeID) async throws -> Trade {
        fetchCount += 1
        if shouldFail { throw AppError.unknown(message: "not found") }
        guard let trade = samples.first(where: { $0.id == id }) else {
            throw AppError.unknown(message: "not found")
        }
        return trade
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: samples, nextCursor: nil)
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] { samples }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: samples, nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade { previous }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw AppError.unknown(message: "stub")
    }
    func updateAccount(id: TradingAccountID, ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw AppError.unknown(message: "stub")
    }
    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws {}
    func updateAccountNote(id: TradingAccountID, note: String?) async throws {}
    func importCSVTrades(_ drafts: [TradeDraft], isInitialImport: Bool) async throws -> Int { 0 }
}

private final class PushUploadCounter: @unchecked Sendable {
    var value = 0
}
