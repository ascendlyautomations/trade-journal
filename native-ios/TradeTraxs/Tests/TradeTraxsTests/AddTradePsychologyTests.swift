import XCTest
@testable import TradeTraxs

final class TradeReviewCatalogTests: XCTestCase {
    func testResolvedTimeframeUsesPreset() {
        XCTAssertEqual(
            TradeReviewCatalog.resolvedTimeframe(selection: "5m", custom: ""),
            "5m"
        )
    }

    func testResolvedTimeframeUsesCustomValue() {
        XCTAssertEqual(
            TradeReviewCatalog.resolvedTimeframe(selection: TradeReviewCatalog.customTimeframeToken, custom: "45 Second"),
            "45 Second"
        )
    }

    func testTimeframeSelectionMapsStoredPreset() {
        let mapped = TradeReviewCatalog.timeframeSelection(for: "1hr")
        XCTAssertEqual(mapped.selection, "1hr")
        XCTAssertEqual(mapped.custom, "")
    }

    func testTimeframeSelectionMapsUnknownStoredValueToCustom() {
        let mapped = TradeReviewCatalog.timeframeSelection(for: "45 Second")
        XCTAssertEqual(mapped.selection, TradeReviewCatalog.customTimeframeToken)
        XCTAssertEqual(mapped.custom, "45 Second")
    }

    func testPsychologySummaryPlaceholderWhenEmpty() {
        XCTAssertEqual(
            TradeReviewCatalog.psychologySummary(
                confidence: 0,
                emotion: "",
                followedPlan: false,
                marketCondition: "",
                psychologyNotes: ""
            ),
            "Add psychology details"
        )
    }

    func testPsychologySummaryShowsConvictionAndEmotion() {
        XCTAssertEqual(
            TradeReviewCatalog.psychologySummary(
                confidence: 4,
                emotion: "Calm",
                followedPlan: false,
                marketCondition: "",
                psychologyNotes: ""
            ),
            "Conviction 4/5 • Calm"
        )
    }

    func testPsychologySummaryIncludesMarketAndFollowedPlan() {
        XCTAssertEqual(
            TradeReviewCatalog.psychologySummary(
                confidence: 3,
                emotion: "",
                followedPlan: true,
                marketCondition: "Trending",
                psychologyNotes: ""
            ),
            "Conviction 3/5 • Trending • Followed plan"
        )
    }
}

final class TradePsychologyMapperTests: XCTestCase {
    func testInsertBodyIncludesPsychologyFields() {
        var draft = TradeDraft(
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: .now,
            visibility: .private
        )
        draft.confidence = 4
        draft.emotion = "Calm"
        draft.followedPlan = true
        draft.marketCondition = "Trending"
        draft.timeframe = "5m"
        draft.newsEvent = true
        draft.psychologyNotes = "Waited for confirmation."

        let body = TradeMapper.insertBody(from: draft, userID: UserID("user-1"))
        XCTAssertEqual(body.confidence, 4)
        XCTAssertEqual(body.emotion, "Calm")
        XCTAssertEqual(body.followed_plan, true)
        XCTAssertEqual(body.market_condition, "Trending")
        XCTAssertEqual(body.timeframe, "5m")
        XCTAssertEqual(body.news_event, true)
        XCTAssertEqual(body.psychology_notes, "Waited for confirmation.")
    }

    func testMapToDomainRoundTripsPsychologyFields() throws {
        let dto = TradeDTO.Trade(
            id: "t1",
            user_id: "user-1",
            ticker: "NQ",
            direction: "Long",
            contracts: FlexibleNumber(1),
            entry_time: ISO8601.string(from: Date()),
            created_at: ISO8601.string(from: Date()),
            date: ISO8601.string(from: Date()),
            confidence: FlexibleNumber(5),
            emotion: "Focused",
            followed_plan: false,
            market_condition: "Volatile",
            timeframe: "15m",
            news_event: true,
            psychology_notes: "Stayed patient."
        )

        let trade = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(trade.confidence, 5)
        XCTAssertEqual(trade.emotion, "Focused")
        XCTAssertEqual(trade.followedPlan, false)
        XCTAssertEqual(trade.marketCondition, "Volatile")
        XCTAssertEqual(trade.timeframe, "15m")
        XCTAssertEqual(trade.newsEvent, true)
        XCTAssertEqual(trade.psychologyNotes, "Stayed patient.")
    }

    func testUpdateBodyEncodesNilConfidenceWithoutWipingOtherFields() {
        var draft = TradeDraft(
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: .now,
            visibility: .private
        )
        draft.emotion = "Calm"
        draft.followedPlan = true
        draft.newsEvent = false

        let body = TradeMapper.updateBody(from: draft, createdAt: .now)
        XCTAssertNil(body.confidence)
        XCTAssertEqual(body.emotion, "Calm")
        XCTAssertEqual(body.followed_plan, true)
        XCTAssertEqual(body.news_event, false)
    }
}

@MainActor
final class AddTradePsychologyViewModelTests: XCTestCase {
    #if DEBUG
    func testApplyTradeHydratesPsychologyFields() {
        let trade = Trade(
            id: TradeID("t-psych"),
            ownerProfileID: ProfileID("viewer"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: .now,
            exitAt: nil,
            realizedPnL: Money(amount: 100),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: "Preview only",
            notes: "Full journal notes",
            strategy: "ORB",
            timeframe: "5m",
            newsEvent: true,
            confidence: 3,
            emotion: "Calm",
            followedPlan: true,
            marketCondition: "Trending",
            psychologyNotes: "Felt good about the setup.",
            createdAt: .now,
            updatedAt: .now
        )

        let viewModel = AddTradeViewModel(
            trades: AddTradePsychologyStubRepository(),
            feed: AddTradePsychologyStubFeed(),
            session: AddTradePsychologyStubSession(),
            detailCache: DetailPresentationCache(),
            uploadService: AddTradePsychologyStubUpload(),
            objectStorage: AddTradePsychologyStubStorage(),
            mode: .edit(trade.id),
            onDismiss: {}
        )
        viewModel.applyTradeForTesting(trade)

        XCTAssertEqual(viewModel.notesText, "Full journal notes")
        XCTAssertEqual(viewModel.strategyText, "ORB")
        XCTAssertEqual(viewModel.timeframeSelection, "5m")
        XCTAssertTrue(viewModel.newsEvent)
        XCTAssertEqual(viewModel.confidenceLevel, 3)
        XCTAssertEqual(viewModel.emotionSelection, "Calm")
        XCTAssertTrue(viewModel.followedPlan)
        XCTAssertEqual(viewModel.marketConditionSelection, "Trending")
        XCTAssertEqual(viewModel.psychologyNotesText, "Felt good about the setup.")
        XCTAssertEqual(viewModel.psychologySummary, "Conviction 3/5 • Calm • Trending • Followed plan")
    }
    #endif

    func testCopyNotesToCaptionDoesNotMutateNotes() {
        let viewModel = AddTradeViewModel(
            trades: AddTradePsychologyStubRepository(),
            feed: AddTradePsychologyStubFeed(),
            session: AddTradePsychologyStubSession(),
            detailCache: DetailPresentationCache(),
            uploadService: AddTradePsychologyStubUpload(),
            objectStorage: AddTradePsychologyStubStorage(),
            onDismiss: {}
        )
        viewModel.notesText = "Liquidity sweep + VWAP reclaim"
        viewModel.publicCaptionText = ""

        viewModel.copyNotesToCaption()

        XCTAssertEqual(viewModel.publicCaptionText, "Liquidity sweep + VWAP reclaim")
        XCTAssertEqual(viewModel.notesText, "Liquidity sweep + VWAP reclaim")
    }
}

private struct AddTradePsychologyStubSession: SessionProviding {
    var currentUserID: UserID? { UserID("viewer") }
    var accessToken: String? { "token" }
}

private struct AddTradePsychologyStubUpload: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct AddTradePsychologyStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String { path }
    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? { URL(string: "https://example.com/\(path)") }
}

private struct AddTradePsychologyStubFeed: FeedRepository {
    func feed(scope: FeedScope, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }
    func post(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func createPost(_ post: Post) async throws -> Post { post }
    func deletePost(id: PostID) async throws {}
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        CursorPage(items: [], nextCursor: nil)
    }
    func addComment(_ comment: Comment) async throws -> Comment { comment }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {}
    func stories(for viewer: ProfileID) async throws -> [Story] { [] }
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        Story(
            id: StoryID("s"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: .now,
            createdAt: .now,
            viewerHasSeen: false
        )
    }
    func reel(id: ReelID) async throws -> Reel { throw AppError.unknown(message: "stub") }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> [Reel] { [] }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}

private struct AddTradePsychologyStubRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(ownedBy profileID: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        TradeStatistics(tradeCount: 0, winCount: 0, lossCount: 0, totalPnL: Money(amount: 0), averagePnL: Money(amount: 0), averageRiskReward: nil, winRate: 0)
    }
}
