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
            navigationCoordinator: environment.navigation.coordinator
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
