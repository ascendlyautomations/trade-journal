import XCTest
@testable import TradeTraxs

@MainActor
final class TradeDetailExperienceTests: XCTestCase {
    func testImagePipelineResolvesStoragePathViaPublicURL() async throws {
        let storage = RecordingObjectStorage(
            publicBase: URL(string: "https://example.supabase.co")!
        )
        let pipeline = DefaultImagePipeline(
            cache: InMemoryImageCache(),
            storage: storage,
            downloadService: FailingDownloadService(),
            urlSession: URLSession(configuration: .ephemeral)
        )

        // Path-shaped reference — must ask storage for public URL (web parity).
        let reference = MediaReference(
            id: "user-1/1712345678-chart.jpg",
            kind: .image,
            altText: nil
        )
        let url = MediaURLResolver.url(
            for: reference,
            bucket: .screenshots,
            storage: storage
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://example.supabase.co/storage/v1/object/public/screenshots/user-1/1712345678-chart.jpg"
        )

        // Absolute HTTPS still works without storage.
        let absolute = MediaReference(
            id: "https://cdn.example.com/shot.jpg",
            kind: .image,
            altText: nil
        )
        let absoluteURL = MediaURLResolver.url(
            for: absolute,
            bucket: .screenshots,
            storage: storage
        )
        XCTAssertEqual(absoluteURL?.absoluteString, "https://cdn.example.com/shot.jpg")
        _ = pipeline
    }

    func testTradeDetailShowsAccountNameFromCache() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.trade-detail-account")
        let trade = ProfileTradeFixtures.samples(owner: profileID)[0]
        let cache = environment.data.detailCache
        cache.seed(trade)
        cache.seed(accounts: PropFirmFixtures.accounts(owner: profileID), for: profileID)

        let viewModel = TradeDetailViewModel(
            tradeID: trade.id,
            trades: environment.data.trades,
            profiles: environment.data.profiles,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            cache: cache,
            navigationCoordinator: environment.navigation.coordinator,
            rpc: environment.data.rpc
        )
        viewModel.loadIfNeeded()
        for _ in 0..<30 {
            if viewModel.phase == .loaded, viewModel.accountName != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(viewModel.accountName, "Alpha Futures")
        // Non-owner session → public title never includes account number.
        XCTAssertEqual(viewModel.accountIdentityLine, "Alpha Futures")
        XCTAssertFalse(viewModel.accountIdentityLine?.contains("500123") == true)
        XCTAssertEqual(viewModel.mediaReference?.id.contains("http"), true)
    }

    func testAccountStatusTitlesMatchWebLabels() {
        XCTAssertEqual(TradeDisplay.accountStatusTitle(.funded), "Funded")
        XCTAssertEqual(TradeDisplay.accountStatusTitle(.evaluation), "Evaluation")
        XCTAssertEqual(TradeDisplay.accountStatusTitle(.live), "Live")
        XCTAssertEqual(TradeDisplay.accountModeCompactTitle(.evaluation), "Eval")
        XCTAssertEqual(TradeDisplay.sideTitle(.long), "Long")
        XCTAssertEqual(TradeDisplay.sideTitle(.short), "Short")
    }

    func testTradeDetailExperiencesAreDistinct() {
        XCTAssertNotEqual(TradeDetailExperience.journal, TradeDetailExperience.social)
    }

    func testAccountIdentityLineUsesOwnerVersusPublicRules() {
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Alpha Futures",
                size: 50_000,
                mode: .evaluation,
                accountNumber: "500123",
                audience: .owner
            ),
            "Alpha Futures • 500123"
        )
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Alpha Futures",
                size: 50_000,
                mode: .evaluation,
                accountNumber: "500123",
                audience: .public
            ),
            "Alpha Futures"
        )
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Tradovate Personal",
                accountNumber: nil,
                audience: .owner
            ),
            "Tradovate Personal"
        )
    }

    func testPointsTextUsesAuthoritativeField() {
        XCTAssertEqual(TradeDisplay.pointsText(Decimal(string: "16.5")), "+16.5")
        XCTAssertEqual(TradeDisplay.pointsText(Decimal(string: "-4")), "-4")
        XCTAssertNil(TradeDisplay.pointsText(nil))
    }

    func testHoldDurationPrefersStoredDurationText() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("dev.points"))[0]
        trade.durationText = "2h 15m"
        trade.durationSeconds = nil
        XCTAssertEqual(TradeDisplay.holdDuration(for: trade), "2h 15m")
    }

    func testHoldDurationFallsBackToEntryExit() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("dev.points"))[0]
        trade.durationText = nil
        trade.durationSeconds = nil
        trade.entryAt = Date(timeIntervalSince1970: 0)
        trade.exitAt = Date(timeIntervalSince1970: 3_700)
        XCTAssertEqual(TradeDisplay.holdDuration(for: trade), "1h 1m")
    }

    func testPriceTextUsesCurrencyGroupingAndDecimals() {
        XCTAssertEqual(TradeDisplay.priceText(Decimal(string: "20153.25")), "$20,153.25")
        XCTAssertEqual(TradeDisplay.priceText(Decimal(18_420)), "$18,420")
        XCTAssertEqual(TradeDisplay.priceText(nil), "—")
    }

    func testCompactDateTimeFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 7,
            day: 31,
            hour: 9,
            minute: 37
        )
        let date = calendar.date(from: components)!
        // Formatter is locale-fixed; assert shape without depending on device TZ by
        // formatting a known local construction through the shared API after pinning.
        let formatted = TradeDisplay.dateTimeText(date)
        XCTAssertFalse(formatted.contains(","))
        XCTAssertFalse(formatted.contains(" at "))
        XCTAssertTrue(formatted.contains("AM") || formatted.contains("PM"))
        // `M/d/yy` — no leading zeros on month/day.
        let pattern = #"^\d{1,2}:\d{2}(AM|PM) \d{1,2}/\d{1,2}/\d{2}$"#
        XCTAssertNotNil(formatted.range(of: pattern, options: .regularExpression), formatted)
    }

    func testPublicURLPreservesMultiSegmentPaths() {
        let storage = RecordingObjectStorage(
            publicBase: URL(string: "https://proj.supabase.co/")!
        )
        let url = storage.publicURL(bucket: "screenshots", path: "abc/def/ghi.jpg")
        XCTAssertEqual(
            url?.absoluteString,
            "https://proj.supabase.co/storage/v1/object/public/screenshots/abc/def/ghi.jpg"
        )
        XCTAssertFalse(url?.absoluteString.contains("%2F") == true)
    }

    func testExecutionTimestampTextUsesTimeOnlyOnSameDay() {
        let entry = Date(timeIntervalSince1970: 1_700_000_000)
        let exitSameDay = entry.addingTimeInterval(900)
        var trade = makeAnalyticsTrade(id: "same", ticker: "NQ", pnl: 437, rr: 7.1, dayOffset: 0)
        trade.entryAt = entry
        trade.exitAt = exitSameDay

        XCTAssertFalse(TradeDisplay.entryExecutionTimeText(for: trade).contains("·"))
        XCTAssertFalse(TradeDisplay.exitExecutionTimeText(for: trade).contains("·"))

        trade.exitAt = entry.addingTimeInterval(86_400 + 900)
        XCTAssertTrue(TradeDisplay.entryExecutionTimeText(for: trade).contains("·"))
        XCTAssertTrue(TradeDisplay.exitExecutionTimeText(for: trade).contains("·"))
    }

    func testExitExecutionTimeTextShowsDashWhenMissing() {
        var trade = makeAnalyticsTrade(id: "open", ticker: "NQ", pnl: 0, rr: 1, dayOffset: 0)
        trade.exitAt = nil
        XCTAssertEqual(TradeDisplay.exitExecutionTimeText(for: trade), "—")
    }

    func testCompactRRTextFormatsSignedMultiple() {
        XCTAssertEqual(TradeDisplay.compactRRText(Decimal(string: "7.1")), "+7.1R")
        XCTAssertEqual(TradeDisplay.compactRRText(Decimal(string: "-2.4")), "-2.4R")
        XCTAssertNil(TradeDisplay.compactRRText(nil))
    }

    func testTradeDetailAnalyticsComparesAgainstOwnerHistory() {
        let owner = ProfileID("user-analytics")
        let current = makeAnalyticsTrade(id: "current", ticker: "MNQ", pnl: 437, rr: 7.1, dayOffset: 0)
        let history = (1...12).map { index in
            makeAnalyticsTrade(
                id: "h\(index)",
                ticker: index <= 8 ? "MNQ" : "ES",
                pnl: index.isMultiple(of: 3) ? 120 : -40,
                rr: 1.8,
                dayOffset: index
            )
        }

        let result = TradeDetailAnalytics.analyze(trade: current, history: history + [current])
        XCTAssertNotNil(result.cohort)
        XCTAssertEqual(result.tickerHistory?.previousTradeCount, 8)
        XCTAssertTrue(result.tickerHistory?.comparisonSentence.contains("previous 8 MNQ") == true)
    }

    func testTickerHistoryUsesNetPnLAndExcludesCurrentTrade() {
        let owner = ProfileID("user-net")
        var current = makeAnalyticsTrade(id: "current", ticker: "MNQ", pnl: 500, rr: 2, dayOffset: 0)
        current.ownerProfileID = owner
        var win = makeAnalyticsTrade(id: "w1", ticker: "MNQ", pnl: 300, rr: 2, dayOffset: 1)
        win.ownerProfileID = owner
        var loss = makeAnalyticsTrade(id: "l1", ticker: "MNQ", pnl: -100, rr: -1, dayOffset: 2)
        loss.ownerProfileID = owner
        var duplicate = win

        let result = TradeDetailAnalytics.analyze(
            trade: current,
            history: [current, win, loss, duplicate]
        )

        XCTAssertEqual(result.tickerHistory?.previousTradeCount, 2)
        XCTAssertEqual(result.tickerHistory?.totalPnL, 200)
        XCTAssertEqual(result.tickerHistory?.avgTradePnL, 100)
        XCTAssertEqual(result.tickerHistory?.profitFactor, 3)
    }

    func testTickerHistoryNormalizesContractSuffix() {
        let owner = ProfileID("user-root")
        var current = makeAnalyticsTrade(id: "current", ticker: "MNQ", pnl: 100, rr: 1, dayOffset: 0)
        current.ownerProfileID = owner
        var prior = makeAnalyticsTrade(id: "p1", ticker: "MNQU26", pnl: 50, rr: 1, dayOffset: 1)
        prior.ownerProfileID = owner

        let result = TradeDetailAnalytics.analyze(trade: current, history: [prior, current])
        XCTAssertEqual(result.tickerHistory?.previousTradeCount, 1)
        XCTAssertEqual(result.tickerHistory?.totalPnL, 50)
    }

    func testTickerHistoryExcludesBacktestRows() {
        let owner = ProfileID("user-bt")
        var current = makeAnalyticsTrade(id: "current", ticker: "MNQ", pnl: 100, rr: 1, dayOffset: 0)
        current.ownerProfileID = owner
        var live = makeAnalyticsTrade(id: "live", ticker: "MNQ", pnl: 50, rr: 1, dayOffset: 1)
        live.ownerProfileID = owner
        var backtest = makeAnalyticsTrade(id: "bt", ticker: "MNQ", pnl: 9_999, rr: 9, dayOffset: 2)
        backtest.ownerProfileID = owner
        backtest.mode = .backtest

        let result = TradeDetailAnalytics.analyze(trade: current, history: [live, backtest, current])
        XCTAssertEqual(result.tickerHistory?.previousTradeCount, 1)
        XCTAssertEqual(result.tickerHistory?.totalPnL, 50)
    }

    private func makeAnalyticsTrade(
        id: String,
        ticker: String,
        pnl: Decimal,
        rr: Decimal,
        dayOffset: Int
    ) -> Trade {
        let entry = Date(timeIntervalSince1970: Double(dayOffset) * 86_400)
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("user-analytics"),
            accountID: nil,
            symbol: Symbol(ticker: ticker),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: 20_000,
            exitPrice: 20_100,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(522),
            realizedPnL: Money(amount: pnl),
            riskReward: rr,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            createdAt: entry,
            updatedAt: entry
        )
    }
}

private struct RecordingObjectStorage: ObjectStorageProviding {
    let publicBase: URL

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data {
        throw AppError.network(.connectivity)
    }

    func delete(bucket: String, path: String) async throws {}

    func publicURL(bucket: String, path: String) -> URL? {
        var root = publicBase.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/storage/v1/object/public/\(bucket)/\(path)")
    }
}

private struct FailingDownloadService: DownloadService {
    func download(_ request: DownloadRequest) async throws -> Data {
        throw AppError.network(.connectivity)
    }
}
