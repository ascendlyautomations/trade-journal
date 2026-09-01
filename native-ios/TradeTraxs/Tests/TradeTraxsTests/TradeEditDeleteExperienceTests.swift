import XCTest
@testable import TradeTraxs

@MainActor
final class TradeEditDeleteExperienceTests: XCTestCase {
    override func tearDown() {
        TradeJournalMutationStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        BackendV2BootstrapDiskCache.clearAll()
        super.tearDown()
    }

    func testEditTradeFullScreenDestination() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let tradeID = TradeID("trade-edit-1")
        coordinator.editTrade(tradeID)
        XCTAssertEqual(store.presentedFullScreen, .editTrade(tradeID))
    }

    func testUpdateBodyPreservesCreatedAtAndCoreFields() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = TradeDraft(
            accountID: TradingAccountID("acct-1"),
            accountName: "Alpha 50K",
            accountSizeLabel: "50000",
            accountModeLabel: "evaluation",
            accountCategoryLabel: "propFirm",
            symbol: Symbol(ticker: "mnq"),
            side: .short,
            mode: .live,
            quantity: 3,
            entryPrice: 21000,
            exitPrice: 20950,
            entryAt: Date(timeIntervalSince1970: 1_700_000_100),
            exitAt: Date(timeIntervalSince1970: 1_700_000_200),
            realizedPnL: Money(amount: 250),
            riskReward: 1.5,
            points: 50,
            sessionLabel: "NY",
            strategy: "ORB",
            visibility: .public,
            publicCaption: "Shared",
            noteBody: "Updated notes",
            imageURL: nil
        )
        let body = TradeMapper.updateBody(from: draft, createdAt: createdAt)
        XCTAssertEqual(body.ticker, "MNQ")
        XCTAssertEqual(body.direction, "Short")
        XCTAssertEqual(body.contracts, 3)
        XCTAssertEqual(body.pnl, 250)
        XCTAssertEqual(body.rr, 1.5)
        XCTAssertEqual(body.points, 50)
        XCTAssertEqual(body.is_public, true)
        XCTAssertEqual(body.account_name, "Alpha 50K")
        XCTAssertEqual(body.notes, "Updated notes")
        XCTAssertNil(body.image_url)
        XCTAssertEqual(body.created_at, ISO8601.string(from: createdAt))
    }

    func testEditViewModelHydratesAndSavesViaUpdate() async {
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        // Non-dev user so save goes through repository.update (not fixture short-circuit).
        let owner = ProfileID("user.edit-test")
        let trade = sampleTrade(id: "edit-1", owner: owner.rawValue)
        cache.seed(trade)
        cache.seed(accounts: AddTradeFixtures.accounts(owner: owner), for: owner)
        let repository = EditTradeStubRepository(seed: trade)
        var dismissed = false
        let viewModel = AddTradeViewModel(
            trades: repository,
            feed: EditTradeStubFeedRepository(),
            session: EditTradeStubSession(userID: owner.rawValue),
            detailCache: cache,
            uploadService: EditTradeStubUpload(),
            objectStorage: EditTradeStubStorage(),
            mode: .edit(trade.id),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready && viewModel.symbolText == "MNQ" }
        XCTAssertTrue(viewModel.isEditing)
        XCTAssertEqual(viewModel.navigationTitle, "Edit Trade")
        XCTAssertEqual(viewModel.pnlText, "100")

        viewModel.pnlText = "175"
        viewModel.save()
        await waitFor { dismissed }
        XCTAssertEqual(repository.updateCalls, 1)
        XCTAssertEqual(cache.trade(id: trade.id)?.realizedPnL?.amount, 175)
        if case .updated(let updated) = TradeJournalMutationStore.shared.latest {
            XCTAssertEqual(updated.realizedPnL?.amount, 175)
        } else {
            XCTFail("Expected noteUpdated mutation")
        }
    }

    func testDeleteMutationClearsSessionCaches() {
        let owner = ProfileID("dev.edit-delete")
        let trade = sampleTrade(id: "del-1", owner: owner.rawValue)
        let cache = DetailPresentationCache()
        cache.seed(trade)
        SessionOwnerTradesStore.shared.seed([trade], for: owner, detailCache: cache)
        CalendarMonthSessionStore.shared.store([trade], year: 2026, month: 6)
        let filters = TradeHistoryFilters()
        TradeHistorySessionStore.shared.save(
            TradeHistorySessionStore.Snapshot(
                queryKey: TradeHistorySessionStore.queryKey(
                    profileID: owner,
                    filters: filters,
                    searchText: ""
                ),
                profileID: owner,
                items: [trade],
                nextCursor: nil,
                filters: filters,
                searchText: "",
                loadedAt: Date()
            )
        )

        cache.removeTrade(id: trade.id)
        TradeJournalMutationStore.shared.noteDeleted(id: trade.id, owner: owner)

        XCTAssertNil(cache.trade(id: trade.id))
        XCTAssertEqual(SessionOwnerTradesStore.shared.cached(for: owner)?.isEmpty, true)
        XCTAssertEqual(
            TradeHistorySessionStore.shared.restore(
                profileID: owner,
                filters: filters,
                searchText: ""
            )?.items.isEmpty,
            true
        )
        if case .deleted(let id, let deletedOwner) = TradeJournalMutationStore.shared.latest {
            XCTAssertEqual(id, trade.id)
            XCTAssertEqual(deletedOwner, owner)
        } else {
            XCTFail("Expected noteDeleted mutation")
        }
    }

    func testApplyUpdatedRefreshesTradeDetailWithoutReload() async {
        let environment = CompositionRoot.bootstrap()
        TradeJournalMutationStore.shared.configure(detailCache: environment.data.detailCache)
        let owner = ProfileID("dev.detail-update")
        let trade = sampleTrade(id: "detail-upd-1", owner: owner.rawValue)
        let cache = environment.data.detailCache
        cache.seed(trade)

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
        await waitFor { viewModel.phase == .loaded }

        var updated = trade
        updated.realizedPnL = Money(amount: 420)
        updated.symbol = Symbol(ticker: "ES")
        TradeJournalMutationStore.shared.noteUpdated(updated)
        viewModel.handleJournalMutation()

        XCTAssertEqual(viewModel.trade?.symbol.ticker, "ES")
        XCTAssertEqual(viewModel.trade?.realizedPnL?.amount, 420)
    }

    func testNoteUpdatedPropagatesOwnerTradesAndDetailCache() {
        let owner = ProfileID("user.mutation-propagation")
        let cache = DetailPresentationCache()
        TradeJournalMutationStore.shared.configure(detailCache: cache)
        var trade = sampleTrade(id: "prop-1", owner: owner.rawValue)
        trade.riskReward = 3.5
        trade.realizedPnL = Money(amount: 420)
        SessionOwnerTradesStore.shared.seed([trade], for: owner, detailCache: cache)

        var updated = trade
        updated.riskReward = 4.25
        updated.realizedPnL = Money(amount: 500)
        TradeJournalMutationStore.shared.noteUpdated(updated)

        XCTAssertEqual(cache.trade(id: trade.id)?.riskReward, 4.25)
        XCTAssertEqual(cache.trade(id: trade.id)?.realizedPnL?.amount, 500)
        XCTAssertEqual(
            SessionOwnerTradesStore.shared.cached(for: owner)?.first(where: { $0.id == trade.id })?.riskReward,
            4.25
        )
    }

    func testParseOptionalRiskRewardAcceptsColonFormat() {
        XCTAssertEqual(
            AddTradeViewModel.parseOptionalRiskReward("1 : 2.35"),
            Decimal(string: "2.35")
        )
        XCTAssertEqual(
            AddTradeViewModel.parseOptionalRiskReward("1:3"),
            Decimal(string: "3")
        )
    }

    func testDashboardBootstrapDiskCachePatchesTradeRRAfterMutation() throws {
        let owner = ProfileID("11111111-1111-1111-1111-111111111111")
        let bootstrap: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(dashboardBootstrapFixtureWithRR2.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboard(bootstrap, viewerID: owner.rawValue)

        var updated = sampleTrade(id: "trade-1", owner: owner.rawValue)
        updated.riskReward = 9
        updated.realizedPnL = Money(amount: 777)
        TradePersistedCacheCoordinator.noteUpserted(updated)

        let reloaded = BackendV2BootstrapDiskCache.loadDashboard(viewerID: owner.rawValue)
        let row = reloaded?.bootstrap.data.trade_window.first { $0.id == "trade-1" }
        XCTAssertEqual(row?.rr?.value, 9)
        XCTAssertEqual(row?.pnl?.value, 777)
    }

    // MARK: - Helpers

    private var dashboardBootstrapFixtureWithRR2: String {
        """
        {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[],"trade_window":[{"id":"trade-1","user_id":"11111111-1111-1111-1111-111111111111","ticker":"MNQ","direction":"Long","entry_time":"2026-08-01T12:00:00.000Z","created_at":"2026-08-01T12:00:00.000Z","pnl":100,"rr":2,"points":10,"mode":"live"}],"trade_window_meta":{"limit":500,"returned":1,"history_complete":true,"total_trade_count":1,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
    }

    private func sampleTrade(id: String, owner: String) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID(owner),
            accountID: TradingAccountID("dev.addtrade.personal"),
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 21000,
            exitPrice: 21050,
            entryAt: Date(timeIntervalSince1970: 1_781_337_600), // 2026-06-10-ish
            exitAt: Date(timeIntervalSince1970: 1_781_338_200),
            realizedPnL: Money(amount: 100),
            riskReward: 2,
            points: 50,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: "Seed note",
            strategy: "ORB",
            createdAt: Date(timeIntervalSince1970: 1_781_337_600),
            updatedAt: Date(timeIntervalSince1970: 1_781_337_600)
        )
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private struct EditTradeStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? { get async { userID.map { UserID($0) } } }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}

private final class EditTradeStubRepository: TradeRepository, @unchecked Sendable {
    private let seed: Trade
    private(set) var updateCalls = 0

    init(seed: Trade) { self.seed = seed }

    func trade(id: TradeID) async throws -> Trade {
        guard id == seed.id else { throw AppError.unknown(message: "missing") }
        return seed
    }

    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [seed], nextCursor: nil)
    }

    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, entryFrom: Date, entryTo: Date, limit: Int) async throws -> [Trade] {
        [seed]
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "create not expected")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }

    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade {
        updateCalls += 1
        var trade = previous
        trade.id = id
        trade.accountID = draft.accountID
        trade.symbol = draft.symbol
        trade.side = draft.side
        trade.mode = draft.mode
        trade.quantity = draft.quantity
        trade.entryPrice = draft.entryPrice
        trade.exitPrice = draft.exitPrice
        trade.entryAt = draft.entryAt
        trade.exitAt = draft.exitAt
        trade.realizedPnL = draft.realizedPnL
        trade.riskReward = draft.riskReward
        trade.points = draft.points
        trade.sessionLabel = draft.sessionLabel
        trade.strategy = draft.strategy
        trade.visibility = draft.visibility
        trade.publicCaption = draft.publicCaption
        trade.notePreview = draft.noteBody
        trade.thumbnail = draft.imageURL.map { MediaReference(id: $0, kind: .image, altText: nil) }
        trade.updatedAt = Date()
        return trade
    }

    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        TradeStatistics(tradeCount: 0, winCount: 0, lossCount: 0, totalPnL: Money(amount: 0), averagePnL: Money(amount: 0), averageRiskReward: nil, winRate: 0)
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        AddTradeFixtures.accounts(owner: profileID)
    }
}

private final class EditTradeStubFeedRepository: FeedRepository, @unchecked Sendable {
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
            id: StoryID("stub-story"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
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

private struct EditTradeStubUpload: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct EditTradeStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String { path }
    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(path)")
    }
}
