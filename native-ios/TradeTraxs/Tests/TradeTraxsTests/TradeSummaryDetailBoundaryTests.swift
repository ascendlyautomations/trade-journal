import XCTest
@testable import TradeTraxs

@MainActor
final class TradeSummaryDetailBoundaryTests: XCTestCase {
    func testTradeSummaryWireDecode() throws {
        let json = BackendV2ContractFixtures.profileTabTradesV2
        let bootstrap: ProfileTabBootstrapV2 = try JSONDecoder().decode(ProfileTabBootstrapV2.self, from: Data(json.utf8))
        let summary = try TradeSummaryMapper.map(from: bootstrap.data.items[0])
        XCTAssertEqual(summary.id.rawValue, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual(summary.notePreview, "Held through the open drive.")
    }

    func testDetailMapsToSummaryButSummaryCannotBeDetail() {
        let detail = fullDetailFixture()
        let summary = TradeSummaryMapper.summary(from: detail)
        XCTAssertEqual(summary.id, detail.id)
        let preview = TradeSummaryMapper.previewTrade(from: summary)
        XCTAssertNil(preview.psychologyNotes)
        XCTAssertNil(preview.importSource)
        XCTAssertFalse(TradeDetailCompleteness.isAuthoritative(.listSeed))
        XCTAssertTrue(TradeDetailCompleteness.isAuthoritative(.authoritativeNetwork))
    }

    func testListSeedIsNotAuthoritativeInDetailCache() {
        let cache = DetailPresentationCache()
        let trade = fullDetailFixture()
        cache.seed(trade)
        XCTAssertNil(cache.authoritativeDetail(id: trade.id))
        XCTAssertNotNil(cache.presentationSeed(id: trade.id))
    }

    func testOwnerJournalSelectIncludesDetailFields() {
        XCTAssertTrue(
            TradeDetailCompleteness.detailSelectIncludesJournalFields(TradeDTO.ownerJournalSelect)
        )
    }

    func testTradeDetailRepositorySingleFlightAndCache() async throws {
        let session = RecordingSessionProvider(userID: UserID("viewer-1"))
        let repo = RecordingTradeRepository()
        let detailRepo = DefaultTradeDetailRepository(
            trades: repo,
            session: session,
            store: TradeDetailSessionStore.shared,
            detailCache: DetailPresentationCache()
        )
        await detailRepo.resetSessionCache()

        async let first = detailRepo.load(tradeID: TradeID("t-1"), policy: .default)
        async let second = detailRepo.load(tradeID: TradeID("t-1"), policy: .default)
        _ = try await (first, second)
        XCTAssertEqual(repo.fetchCount, 1)

        _ = await detailRepo.cachedDetail(tradeID: TradeID("t-1"))
        let cached = await detailRepo.cachedDetail(tradeID: TradeID("t-1"))
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.exitEmotion, "Calm")
    }

    func testImagesForTradeDoesNotHydrateFullTradeRow() async throws {
        let repo = RecordingTradeRepository()
        _ = try await repo.images(for: TradeID("t-1"))
        XCTAssertEqual(repo.fetchCount, 0)
    }

    func testViewerIsolationClearsSeparateBuckets() async throws {
        let store = TradeDetailSessionStore.shared
        await store.resetAll()
        let detail = fullDetailFixture()
        await store.store(
            detail,
            tradeID: detail.id,
            viewerKey: "viewer-a",
            authority: .authoritativeNetwork,
            payloadBytes: 100
        )
        let otherViewer = await store.cachedDetail(tradeID: detail.id, viewerKey: "viewer-b")
        XCTAssertNil(otherViewer)
    }

    private func fullDetailFixture() -> TradeDetail {
        Trade(
            id: TradeID("detail-1"),
            ownerProfileID: ProfileID("owner-1"),
            accountID: TradingAccountID("acct-1"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_600),
            realizedPnL: Money(amount: 50, currencyCode: "USD"),
            riskReward: 2,
            points: 4,
            sessionLabel: "NY",
            visibility: .public,
            publicCaption: "Caption",
            thumbnail: nil,
            imageDisplayMode: .fit,
            notePreview: "Preview",
            notes: "Full notes",
            strategy: "Breakout",
            timeframe: "5m",
            newsEvent: false,
            confidence: 4,
            emotion: "Focused",
            followedPlan: true,
            marketCondition: "Trend",
            psychologyNotes: "Stayed patient",
            exitEmotion: "Calm",
            executionRating: 4,
            durationText: "10m",
            durationSeconds: 600,
            reviewed: true,
            isInitialImport: false,
            importSource: TradeImportSource.manual,
            importFingerprint: "fp-1",
            accountMode: .live,
            publicAccountBadge: "Live",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct RecordingSessionProvider: SessionProviding {
    let userID: UserID
    var currentUserID: UserID? { get async { userID } }
    var accessToken: String? { get async { nil } }
}

private final class RecordingTradeRepository: TradeRepository, @unchecked Sendable {
    private(set) var fetchCount = 0
    private(set) var imagesFetchCount = 0
    private(set) var notesFetchCount = 0

    func trade(id: TradeID) async throws -> Trade {
        fetchCount += 1
        try await Task.sleep(nanoseconds: 50_000_000)
        return Trade(
            id: id,
            ownerProfileID: ProfileID("owner-1"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: .now,
            exitAt: .now,
            realizedPnL: Money(amount: 1, currencyCode: "USD"),
            riskReward: 1,
            points: 1,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            notePreview: nil,
            notes: "notes",
            strategy: nil,
            timeframe: nil,
            newsEvent: nil,
            confidence: nil,
            emotion: nil,
            followedPlan: nil,
            marketCondition: nil,
            psychologyNotes: "psych",
            exitEmotion: "Calm",
            executionRating: 5,
            durationText: nil,
            durationSeconds: nil,
            reviewed: nil,
            isInitialImport: nil,
            importSource: nil,
            importFingerprint: "fp",
            accountMode: nil,
            publicAccountBadge: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }

    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, entryFrom: Date, entryTo: Date, limit: Int) async throws -> [Trade] { [] }

    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.unknown(message: "stub") }

    func update(_ trade: Trade) async throws -> Trade { trade }

    func delete(id: TradeID) async throws {}

    func images(for tradeID: TradeID) async throws -> [TradeImage] {
        imagesFetchCount += 1
        return []
    }

    func notes(for tradeID: TradeID) async throws -> [TradeNote] {
        notesFetchCount += 1
        return []
    }

    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
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
}
