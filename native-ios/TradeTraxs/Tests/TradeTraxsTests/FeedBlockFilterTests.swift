import XCTest
@testable import TradeTraxs

@MainActor
final class FeedBlockFilterTests: XCTestCase {
    override func setUp() async throws {
        FeedBlockedAuthorsFilter.shared.resetForTesting()
    }

    func testBlockedAuthorFilteredFromConversationMessages() {
        let viewer = FeedFixtures.viewerID
        let blocked = ProfileID("blocked-room-author")
        let messages = [
            Message(
                id: MessageID("m1"),
                conversationID: ConversationID("room-channel"),
                senderProfileID: blocked,
                kind: .text,
                body: "blocked",
                attachments: [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            ),
            Message(
                id: MessageID("m2"),
                conversationID: ConversationID("room-channel"),
                senderProfileID: viewer,
                kind: .text,
                body: "mine",
                attachments: [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            ),
        ]
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blocked)
        let visible = FeedBlockedAuthorsFilter.shared.filterConversationMessages(messages, viewerID: viewer)
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.senderProfileID, viewer)
    }

    func testBlockedAuthorFilteredFromFeedEntries() {
        let entries = FeedFixtures.timeline()
        let blockedID = entries.first!.authorProfileID
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blockedID)

        let visible = FeedBlockedAuthorsFilter.shared.filterEntries(entries)
        XCTAssertFalse(visible.contains { $0.authorProfileID == blockedID })
        XCTAssertLessThan(visible.count, entries.count)
    }

    func testBlockImmediatelyRemovesLoadedContent() {
        let entries = FeedFixtures.timeline()
        let blockedID = entries.first!.authorProfileID
        var loaded = entries
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blockedID)
        loaded = FeedBlockedAuthorsFilter.shared.filterEntries(loaded)
        XCTAssertFalse(loaded.contains { $0.authorProfileID == blockedID })
    }

    func testBlockNotificationStripsViewModelVisibleEntries() async {
        let entries = FeedFixtures.timeline()
        let blockedID = entries.first!.authorProfileID
        let viewModel = makeMinimalFeedScreenViewModel()
        viewModel.testing_setLoadedEntries(entries, viewerID: FeedFixtures.viewerID)

        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blockedID)
        NotificationCenter.default.post(name: .userBlockListDidChange, object: nil)
        await Task.yield()

        XCTAssertFalse(viewModel.visibleEntries.contains { $0.authorProfileID == blockedID })
    }

    func testRealtimeDoesNotReinsertBlockedAuthor() async {
        let blockedID = ProfileID("blocked-realtime-author")
        let postID = PostID("blocked-realtime-post")
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blockedID)

        let viewModel = makeMinimalFeedScreenViewModel(
            feed: RealtimeBlockedAuthorFeedRepository(postID: postID, authorID: blockedID)
        )
        viewModel.testing_setLoadedEntries([], viewerID: FeedFixtures.viewerID)

        await viewModel.testing_applyRealtimeSignal(
            MessageRealtimeSignal(kind: .insert, messageID: postID.rawValue, conversationID: nil)
        )

        XCTAssertTrue(viewModel.entries.isEmpty)
    }

    func testUnblockDoesNotReinsertUntilRefresh() {
        let entries = FeedFixtures.timeline()
        let blockedID = entries.first!.authorProfileID
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blockedID)
        let filtered = FeedBlockedAuthorsFilter.shared.filterEntries(entries)
        FeedBlockedAuthorsFilter.shared.noteUnblock(peerID: blockedID)

        XCTAssertEqual(
            FeedBlockedAuthorsFilter.shared.filterEntries(entries).count,
            entries.count
        )
        XCTAssertLessThan(filtered.count, entries.count)
    }

    func testFeedTimelineEntryReportRequestMapsCorrectTargets() {
        let viewer = FeedFixtures.viewerID
        let entries = FeedFixtures.timeline()

        for entry in entries {
            guard let request = entry.reportRequest(viewerID: viewer) else { continue }
            switch entry {
            case .trade(_, let trade):
                XCTAssertEqual(request.target.type, .trade)
                XCTAssertEqual(request.target.targetID, trade.id.rawValue)
            case .post(let item, _):
                XCTAssertEqual(request.target.type, .post)
                XCTAssertEqual(request.target.targetID, item.id)
            case .clip(let item, _):
                XCTAssertEqual(request.target.type, .reel)
                XCTAssertEqual(request.target.targetID, item.id)
            case .achievement(let item, _):
                XCTAssertEqual(request.target.type, .achievement)
                XCTAssertEqual(request.target.targetID, item.id)
            }
            XCTAssertEqual(request.target.reportedUserID, entry.authorProfileID)
        }
    }

    func testFeedTimelineEntryReportRequestNilForOwnContent() {
        let viewer = FeedFixtures.viewerID
        let entries = FeedFixtures.timeline()
        let ownEntry = entries.first { $0.authorProfileID == viewer }
        if let ownEntry {
            XCTAssertNil(ownEntry.reportRequest(viewerID: viewer))
        }
    }

    func testPrivacyManifestExistsWithUserDefaultsDeclaration() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TradeTraxs/App/PrivacyInfo.xcprivacy")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "PrivacyInfo.xcprivacy must ship in the TradeTraxs app target"
        )

        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let accessed = plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        let userDefaults = accessed?.first {
            ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String]
        XCTAssertEqual(reasons, ["CA92.1"])
        XCTAssertEqual(plist?["NSPrivacyTracking"] as? Bool, false)
    }

    private func makeMinimalFeedScreenViewModel(
        feed: (any FeedRepository)? = nil
    ) -> FeedScreenViewModel {
        FeedScreenViewModel(
            feed: feed ?? FeedBlockEmptyFeedRepository(),
            trades: FeedBlockStubTradeRepository(),
            profiles: FeedBlockStubProfileRepository(),
            achievements: FeedBlockStubAchievementRepository(),
            session: FeedBlockStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            engagementStore: EngagementStore(repository: FeedBlockStubInteractionRepository()),
            vaultStore: VaultStore.testInstance(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            messages: FeedBlockStubMessageRepository()
        )
    }
}

private struct FeedBlockStubMessageRepository: MessageRepository {
    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        throw AppError.notImplemented(feature: "conversation")
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }
    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws {}
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createConversation")
    }

    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createDirectConversation")
    }

    func createGroupConversation(viewerID: ProfileID, recipients: [Profile], name: String?) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createGroupConversation")
    }

    func deleteConversation(id: ConversationID) async throws {}
    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}
    func setConversationNotificationsEnabled(conversationID: ConversationID, enabled: Bool) async throws {}
    func fetchActiveBlockPeerIDs() async throws -> Set<ProfileID> { [] }
}

private struct FeedBlockEmptyFeedRepository: FeedRepository {
    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }

    func post(id: PostID) async throws -> Post {
        ProfilePostFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

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
            id: StoryID("stub"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: false
        )
    }

    func deleteStory(id: StoryID) async throws {}
    func reel(id: ReelID) async throws -> ReelLoadResult {
        ReelLoadResult(reel: ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)[0], embeddedTrade: nil)
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
}

private struct RealtimeBlockedAuthorFeedRepository: FeedRepository {
    let postID: PostID
    let authorID: ProfileID

    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }

    func post(id: PostID) async throws -> Post {
        Post(
            id: postID,
            authorProfileID: authorID,
            body: "blocked author post",
            media: [],
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

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
            id: StoryID("stub"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: false
        )
    }

    func deleteStory(id: StoryID) async throws {}
    func reel(id: ReelID) async throws -> ReelLoadResult {
        ReelLoadResult(reel: ProfileClipFixtures.samples(owner: authorID)[0], embeddedTrade: nil)
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
}

private struct FeedBlockStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        ProfileTradeFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        ProfileTradeFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
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
}

private struct FeedBlockStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID(FeedFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        FollowListFixtures.profile(id: id) ?? Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: id.rawValue,
            displayName: id.rawValue,
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        ProfilePostFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}

private struct FeedBlockStubAchievementRepository: AchievementRepository {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        ProfileAchievementFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}

private struct FeedBlockStubInteractionRepository: InteractionRepository {
    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0, .empty) })
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {}
    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment] { [] }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        InteractionComment(
            id: CommentID(UUID().uuidString),
            target: target,
            authorProfileID: FeedFixtures.viewerID,
            authorUsername: nil,
            body: body,
            parentCommentID: parentID,
            createdAt: .now,
            isPinned: false
        )
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {}

    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot] {
        Dictionary(uniqueKeysWithValues: commentIDs.map { ($0, .empty) })
    }

    func setCommentLiked(
        _ liked: Bool,
        commentID: CommentID,
        source: CommentLikeSource
    ) async throws {}

    func setCommentPinned(
        _ pinned: Bool,
        commentID: CommentID,
        on target: InteractionTarget
    ) async throws {}
}

private struct FeedBlockStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "token" }
    }
}
