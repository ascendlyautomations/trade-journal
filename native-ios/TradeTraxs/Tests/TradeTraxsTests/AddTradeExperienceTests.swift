import XCTest
@testable import TradeTraxs

@MainActor
final class AddTradeExperienceTests: XCTestCase {
    override func tearDown() {
        TradeJournalMutationStore.shared.invalidate()
        ContentMutationStore.shared.invalidate()
        super.tearDown()
    }

    func testCreateTabOpensAddTradeFullScreen() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.selectTab(.create)
        XCTAssertEqual(store.presentedSheet, .composeChooser)
        coordinator.dismissSheet()
        coordinator.openCompose(.trade)
        XCTAssertEqual(store.presentedFullScreen, .addTrade)
    }

    func testSessionLabelMatchesWebBuckets() {
        // 10:00 ET → NY; 19:00 ET → Asia
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let ny = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 10))!
        let asia = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 19))!
        XCTAssertEqual(TradingSessionLabel.session(from: ny), "NY")
        XCTAssertEqual(TradingSessionLabel.session(from: asia), "Asia")
        XCTAssertEqual(TradingSessionLabel.easternTradeDateString(from: ny), "2026-06-10")
    }

    func testInsertBodyIncludesCoreQuickTradeFields() {
        let draft = TradeDraft(
            accountID: TradingAccountID("acct-1"),
            accountName: "Alpha 50K",
            accountSizeLabel: "50000",
            accountModeLabel: "evaluation",
            accountCategoryLabel: "propFirm",
            symbol: Symbol(ticker: "mnq"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: 21452.25,
            exitPrice: 21468.75,
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_600),
            realizedPnL: Money(amount: 660),
            riskReward: 2,
            points: 16.5,
            sessionLabel: "NY",
            strategy: "ORB",
            visibility: .private,
            publicCaption: nil,
            noteBody: "Waited for confirmation",
            imageURL: "https://example.com/shot.jpg"
        )
        let body = TradeMapper.insertBody(from: draft, userID: UserID("user-1"))
        XCTAssertEqual(body.ticker, "MNQ")
        XCTAssertEqual(body.direction, "Long")
        XCTAssertEqual(body.contracts, 2)
        XCTAssertEqual(body.pnl, 660)
        XCTAssertEqual(body.points, 16.5)
        XCTAssertEqual(body.session, "NY")
        XCTAssertEqual(body.strategy, "ORB")
        XCTAssertEqual(body.notes, "Waited for confirmation")
        XCTAssertEqual(body.image_url, "https://example.com/shot.jpg")
        XCTAssertEqual(body.is_public, false)
        XCTAssertEqual(body.account_name, "Alpha 50K")
        XCTAssertNotNil(body.trade_date)
        XCTAssertNotNil(body.entry_time)
    }

    func testViewModelRequiresSymbolAndEligibleAccount() async {
        let cache = DetailPresentationCache()
        var dismissed = false
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        XCTAssertFalse(viewModel.eligibleAccounts.isEmpty)

        viewModel.save()
        await waitFor { viewModel.fieldErrors[.symbol] != nil }
        XCTAssertNotNil(viewModel.fieldErrors[.symbol])
        XCTAssertFalse(dismissed)

        viewModel.symbolText = "MNQ"
        viewModel.pnlText = "100"
        viewModel.contractsText = "1"
        viewModel.save()
        await waitFor { dismissed }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(TradeJournalMutationStore.shared.revision, 1)
    }

    func testReadOnlyAccountCannotBeSelected() async throws {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        let readOnly = try XCTUnwrap(viewModel.ineligibleAccounts.first)
        viewModel.selectAccount(readOnly.id)
        XCTAssertNotEqual(viewModel.selectedAccountID, readOnly.id)
        XCTAssertNotNil(viewModel.formError)
    }

    func testExitBeforeEntryFailsValidation() async {
        let cache = DetailPresentationCache()
        var dismissed = false
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "ES"
        viewModel.pnlText = "10"
        viewModel.entryAt = Date()
        viewModel.includeExitTime = true
        viewModel.exitAt = Date().addingTimeInterval(-3_600)
        viewModel.save()
        await waitFor { viewModel.formError != nil }
        XCTAssertFalse(dismissed)
    }

    func testDuplicateSavePreventionWhileSaving() async {
        let cache = DetailPresentationCache()
        let repo = AddTradeSlowRepository()
        var dismissCount = 0
        let viewModel = AddTradeViewModel(
            trades: repo,
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: "user.real"),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: { dismissCount += 1 }
        )
        // Seed accounts via cache so open doesn't wait on network-shaped path.
        cache.seed(accounts: AddTradeFixtures.accounts(owner: ProfileID("user.real")), for: ProfileID("user.real"))
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "NQ"
        viewModel.pnlText = "50"
        viewModel.save()
        viewModel.save()
        await waitFor { dismissCount == 1 }
        XCTAssertEqual(repo.saveCalls, 1)
        XCTAssertEqual(dismissCount, 1)
    }

    func testFailedSavePreservesForm() async {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeFailingRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: "user.real"),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        cache.seed(accounts: AddTradeFixtures.accounts(owner: ProfileID("user.real")), for: ProfileID("user.real"))
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "CL"
        viewModel.pnlText = "-20"
        viewModel.notesText = "Keep me"
        viewModel.save()
        await waitFor { viewModel.formError != nil }
        XCTAssertEqual(viewModel.symbolText, "CL")
        XCTAssertEqual(viewModel.notesText, "Keep me")
        XCTAssertEqual(viewModel.phase, .ready)
    }

    func testMediaSelectionAndRemoval() async {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        #if DEBUG
        viewModel.applyScreenshotMediaFixture()
        XCTAssertNotNil(viewModel.screenshotPreview)
        XCTAssertNotNil(viewModel.screenshotData)
        viewModel.clearScreenshot()
        XCTAssertNil(viewModel.screenshotPreview)
        XCTAssertNil(viewModel.screenshotData)
        #endif
    }

    func testDraftProtectionFlag() async {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        viewModel.symbolText = "ES"
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testShareVisibilityMapsToPublicDraft() {
        let draft = TradeDraft(
            accountID: TradingAccountID("a"),
            symbol: Symbol(ticker: "MNQ"),
            side: .short,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: Money(amount: 10),
            visibility: .public,
            publicCaption: "Nice scalp",
            noteBody: nil
        )
        let body = TradeMapper.insertBody(from: draft, userID: UserID("u1"))
        XCTAssertEqual(body.is_public, true)
        XCTAssertEqual(body.public_description, "Nice scalp")
        XCTAssertEqual(body.direction, "Short")
    }

    func testPropAccountInsertUsesDenormalizedLabels() {
        let draft = TradeDraft(
            accountID: TradingAccountID("prop-1"),
            accountName: "Alpha 50K",
            accountSizeLabel: "50000",
            accountModeLabel: "evaluation",
            accountCategoryLabel: "propFirm",
            symbol: Symbol(ticker: "MES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: Money(amount: 100),
            visibility: .private,
            publicCaption: nil,
            noteBody: nil
        )
        let body = TradeMapper.insertBody(from: draft, userID: UserID("u1"))
        XCTAssertEqual(body.account_category, "propFirm")
        XCTAssertEqual(body.account_type, "evaluation")
        XCTAssertEqual(body.account_name, "Alpha 50K")
    }

    func testLinkReelSelectionAndClear() async throws {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.loadUnattachedReelsIfNeeded()
        await waitFor { !viewModel.unattachedReels.isEmpty }
        let reel = try XCTUnwrap(viewModel.unattachedReels.first)
        viewModel.selectLinkedReel(reel)
        XCTAssertEqual(viewModel.linkedReel?.id, reel.id)
        XCTAssertNil(viewModel.reelDraft)
        viewModel.clearLinkedReel()
        XCTAssertNil(viewModel.linkedReel)
    }

    func testNewClipDraftClearsLinkedReelAndPreservesTradeFields() async {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "MNQ"
        viewModel.pnlText = "660"
        viewModel.loadUnattachedReelsIfNeeded()
        await waitFor { !viewModel.unattachedReels.isEmpty }
        viewModel.selectLinkedReel(viewModel.unattachedReels[0])
        viewModel.applyClipDraftFixture()
        XCTAssertNotNil(viewModel.reelDraft)
        XCTAssertNil(viewModel.linkedReel)
        XCTAssertEqual(viewModel.symbolText, "MNQ")
        XCTAssertEqual(viewModel.pnlText, "660")
        viewModel.clearReelDraft()
        XCTAssertNil(viewModel.reelDraft)
    }

    func testSaveWithClipDraftPublishesWithoutDuplicatingTrade() async {
        let cache = DetailPresentationCache()
        var dismissed = false
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "MNQ"
        viewModel.pnlText = "100"
        viewModel.applyClipDraftFixture()
        viewModel.save()
        await waitFor { dismissed }
        XCTAssertNil(viewModel.tradeAwaitingClip)
        XCTAssertEqual(ContentMutationStore.shared.revision, 1)
        XCTAssertNotNil(ContentMutationStore.shared.latestReelID)
    }

    func testCreateChooserOpensPostAchievementAndReel() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.openCompose(.post)
        XCTAssertEqual(store.presentedFullScreen, .newPost)
        coordinator.dismissFullScreen()
        coordinator.openCompose(.achievement)
        XCTAssertEqual(store.presentedFullScreen, .newAchievement)
        coordinator.dismissFullScreen()
        coordinator.openCompose(.reel)
        XCTAssertEqual(store.presentedFullScreen, .newReel)
        coordinator.dismissFullScreen()
        coordinator.openCompose(.importCSV)
        XCTAssertEqual(store.presentedFullScreen, .importCSV)
    }

    func testCustomInstrumentNormalizesAndApplies() async {
        let cache = DetailPresentationCache()
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: {}
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.applyCustomSymbol("  mgc ")
        XCTAssertEqual(viewModel.symbolText, "MGC")
        XCTAssertNil(viewModel.fieldErrors[.symbol])
        viewModel.applyCustomSymbol("   ")
        XCTAssertEqual(viewModel.fieldErrors[.symbol], "Symbol is required")
    }

    func testRiskRewardFormattingAndParsing() {
        XCTAssertEqual(AddTradeViewModel.formatRiskReward(Decimal(string: "2.35")!), "1 : 2.35")
        XCTAssertEqual(AddTradeViewModel.formatRiskReward(2), "1 : 2")
        XCTAssertEqual(AddTradeViewModel.parseOptionalRiskReward(""), nil)
        XCTAssertEqual(AddTradeViewModel.parseOptionalRiskReward("2.35"), Decimal(string: "2.35"))
        XCTAssertEqual(AddTradeViewModel.parseOptionalRiskReward("1 : 2.35"), Decimal(string: "2.35"))
        XCTAssertNil(AddTradeViewModel.parseOptionalRiskReward("abc"))
        XCTAssertEqual(AddTradeViewModel.normalizeSymbol("  es "), "ES")
    }

    func testInvalidRRFailsValidation() async {
        let cache = DetailPresentationCache()
        var dismissed = false
        let viewModel = AddTradeViewModel(
            trades: AddTradeStubRepository(),
            feed: AddTradeStubFeedRepository(),
            session: AddTradeStubSession(userID: AddTradeFixtures.viewerID.rawValue),
            detailCache: cache,
            uploadService: AddTradeStubUpload(),
            objectStorage: AddTradeStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.symbolText = "NQ"
        viewModel.pnlText = "10"
        viewModel.rrText = "not-a-ratio"
        viewModel.save()
        await waitFor { viewModel.fieldErrors[.rr] != nil }
        XCTAssertFalse(dismissed)
        XCTAssertEqual(viewModel.fieldErrors[.rr], "Enter a valid R:R")
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

private struct AddTradeStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? { get async { userID.map { UserID($0) } } }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}

private final class AddTradeStubFeedRepository: FeedRepository, @unchecked Sendable {
    private(set) var attachCalls = 0
    var shouldFailAttach = false

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
        CursorPage(items: AddTradeFixtures.unattachedReels(owner: profileID), nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> [Reel] {
        AddTradeFixtures.unattachedReels(owner: profileID)
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] {
        Array(AddTradeFixtures.unattachedReels(owner: profileID).prefix(limit))
    }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {
        attachCalls += 1
        if shouldFailAttach {
            throw AppError.unknown(message: "attach failed")
        }
    }
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}

private struct AddTradeStubUpload: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct AddTradeStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String { path }
    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(path)")
    }
}

private struct AddTradeStubRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, entryFrom: Date, entryTo: Date, limit: Int) async throws -> [Trade] { [] }
    func save(_ draft: TradeDraft) async throws -> Trade {
        Trade(
            id: TradeID("saved"),
            ownerProfileID: ProfileID("user"),
            accountID: draft.accountID,
            symbol: draft.symbol,
            side: draft.side,
            mode: draft.mode,
            quantity: draft.quantity,
            entryPrice: draft.entryPrice,
            exitPrice: draft.exitPrice,
            entryAt: draft.entryAt,
            exitAt: draft.exitAt,
            realizedPnL: draft.realizedPnL,
            riskReward: draft.riskReward,
            points: draft.points,
            sessionLabel: draft.sessionLabel,
            visibility: draft.visibility,
            publicCaption: draft.publicCaption,
            thumbnail: nil,
            notePreview: draft.noteBody,
            createdAt: .now,
            updatedAt: .now
        )
    }
    func update(_ trade: Trade) async throws -> Trade { trade }
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

private final class AddTradeSlowRepository: TradeRepository, @unchecked Sendable {
    private(set) var saveCalls = 0
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, entryFrom: Date, entryTo: Date, limit: Int) async throws -> [Trade] { [] }
    func save(_ draft: TradeDraft) async throws -> Trade {
        saveCalls += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return try await AddTradeStubRepository().save(draft)
    }
    func update(_ trade: Trade) async throws -> Trade { trade }
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

private struct AddTradeFailingRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, entryFrom: Date, entryTo: Date, limit: Int) async throws -> [Trade] { [] }
    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "network down")
    }
    func update(_ trade: Trade) async throws -> Trade { trade }
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
