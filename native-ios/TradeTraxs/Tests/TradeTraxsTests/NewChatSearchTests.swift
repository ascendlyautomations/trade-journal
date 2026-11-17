import XCTest
@testable import TradeTraxs

final class SearchQueryNormalizationTests: XCTestCase {
    func testTrimsWhitespace() {
        XCTAssertEqual(SearchQueryNormalization.normalizePeopleQuery("  ada  "), "ada")
    }

    func testStripsLeadingAtSign() {
        XCTAssertEqual(SearchQueryNormalization.normalizePeopleQuery("@trader_a"), "trader_a")
    }

    func testEscapeILikeRemovesFilterBreakers() {
        XCTAssertEqual(SearchQueryNormalization.escapeILikePattern("a(b,c)*"), "a b c")
    }
}

@MainActor
final class NewChatSearchTests: XCTestCase {
    func testSearchByPartialUsernameReturnsResults() async {
        let search = RecordingNewChatSearchRepository()
        let viewModel = makeViewModel(search: search)
        await viewModel.prepare()

        viewModel.searchText = "tra"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(search.lastQuery, "tra")
        XCTAssertFalse(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testAtPrefixNormalizedBeforeSearch() async {
        let search = RecordingNewChatSearchRepository()
        let viewModel = makeViewModel(search: search)

        viewModel.searchText = "@trader"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(search.lastQuery, "trader")
    }

    func testClearingQueryClearsResults() async {
        let search = RecordingNewChatSearchRepository()
        let viewModel = makeViewModel(search: search)
        viewModel.searchText = "peer"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(viewModel.results.isEmpty)

        viewModel.searchText = ""
        viewModel.searchChanged()
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testViewerExcludedFromSearchRequest() async {
        let search = RecordingNewChatSearchRepository()
        let viewer = ProfileID("viewer-1")
        let viewModel = makeViewModel(search: search, viewerID: viewer)
        await viewModel.prepare()

        viewModel.searchText = "peer"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(search.lastExcluding, viewer)
        XCTAssertTrue(viewModel.results.allSatisfy { $0.id != viewer })
    }

    func testStaleSearchDoesNotOverwriteNewerResults() async {
        let search = RecordingNewChatSearchRepository(delayNanoseconds: 400_000_000)
        let viewModel = makeViewModel(search: search)

        viewModel.searchText = "slow"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.searchText = "fast"
        viewModel.searchChanged()
        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(search.lastQuery, "fast")
        XCTAssertEqual(viewModel.results.first?.username, "fast_match")
    }

    func testDismissCancelsOutstandingSearch() async {
        let search = RecordingNewChatSearchRepository(delayNanoseconds: 400_000_000)
        let viewModel = makeViewModel(search: search)

        viewModel.searchText = "peer"
        viewModel.searchChanged()
        viewModel.dismiss()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testPrepareShowsFollowingAndSuggestedWhenFollowingUnderTen() async {
        let viewer = ProfileID("viewer-1")
        let following = (1 ... 5).map { sampleProfile(id: "follow-\($0)") }
        let suggestedPage = (1 ... 15).map { sampleProfile(id: "suggest-\($0)") }
        let profiles = ConfigurableNewChatProfileRepository(following: following)
        let explore = RecordingNewChatExploreRepository(pages: [suggestedPage])
        let viewModel = NewChatViewModel(
            messages: CountingNewChatMessageRepository(),
            search: RecordingNewChatSearchRepository(),
            profiles: profiles,
            explore: explore,
            session: NewChatStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        await viewModel.prepare()

        XCTAssertFalse(viewModel.isLoadingSuggestions)
        XCTAssertEqual(viewModel.followingProfiles.count, 5)
        XCTAssertEqual(viewModel.suggestedProfiles.count, 15)
        XCTAssertTrue(viewModel.showsFollowingSection)
        XCTAssertTrue(viewModel.showsSuggestedSection)
        XCTAssertEqual(explore.discoverCallCount, 1)
    }

    func testPrepareHidesSuggestedWhenFollowingTenOrMore() async {
        let viewer = ProfileID("viewer-1")
        let following = (1 ... 10).map { sampleProfile(id: "follow-\($0)") }
        let explore = RecordingNewChatExploreRepository(pages: [(1 ... 15).map { sampleProfile(id: "suggest-\($0)") }])
        let viewModel = NewChatViewModel(
            messages: CountingNewChatMessageRepository(),
            search: RecordingNewChatSearchRepository(),
            profiles: ConfigurableNewChatProfileRepository(following: following),
            explore: explore,
            session: NewChatStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        await viewModel.prepare()

        XCTAssertEqual(viewModel.followingProfiles.count, 10)
        XCTAssertTrue(viewModel.suggestedProfiles.isEmpty)
        XCTAssertFalse(viewModel.showsSuggestedSection)
        XCTAssertEqual(explore.discoverCallCount, 0)
    }

    func testPrepareSuggestedOnlyWhenNotFollowingAnyone() async {
        let viewer = ProfileID("viewer-1")
        let page0 = (1 ... 15).map { sampleProfile(id: "discover-\($0)") }
        let page1 = (16 ... 20).map { sampleProfile(id: "discover-\($0)") }
        let explore = RecordingNewChatExploreRepository(pages: [page0, page1])
        let viewModel = NewChatViewModel(
            messages: CountingNewChatMessageRepository(),
            search: RecordingNewChatSearchRepository(),
            profiles: ConfigurableNewChatProfileRepository(following: []),
            explore: explore,
            session: NewChatStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        await viewModel.prepare()

        XCTAssertFalse(viewModel.isLoadingSuggestions)
        XCTAssertTrue(viewModel.followingProfiles.isEmpty)
        XCTAssertFalse(viewModel.showsFollowingSection)
        XCTAssertEqual(viewModel.suggestedProfiles.count, 15)
        XCTAssertTrue(viewModel.showsSuggestedSeeMore)

        await viewModel.loadMoreSuggested()
        XCTAssertEqual(viewModel.suggestedProfiles.count, 20)
        XCTAssertFalse(viewModel.showsSuggestedSeeMore)
    }

    func testFollowMutationRefreshesSections() async {
        let viewer = ProfileID("viewer-1")
        let following = (1 ... 9).map { sampleProfile(id: "follow-\($0)") }
        let profiles = ConfigurableNewChatProfileRepository(following: following)
        let explore = RecordingNewChatExploreRepository(pages: [(1 ... 15).map { sampleProfile(id: "suggest-\($0)") }])
        let viewModel = NewChatViewModel(
            messages: CountingNewChatMessageRepository(),
            search: RecordingNewChatSearchRepository(),
            profiles: profiles,
            explore: explore,
            session: NewChatStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        await viewModel.prepare()
        XCTAssertTrue(viewModel.showsSuggestedSection)

        profiles.followingProfiles = (1 ... 10).map { sampleProfile(id: "follow-\($0)") }
        await viewModel.handleFollowRelationshipChange()

        XCTAssertEqual(viewModel.followingProfiles.count, 10)
        XCTAssertFalse(viewModel.showsSuggestedSection)
        XCTAssertTrue(viewModel.suggestedProfiles.isEmpty)
    }

    func testExistingConversationReused() async {
        MessagesInboxStore.shared.resetForTesting()
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewer = MessagesInboxFixtures.viewerID
        let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada"))!

        let repo = CountingNewChatMessageRepository()
        let viewModel = NewChatViewModel(
            messages: repo,
            search: RecordingNewChatSearchRepository(),
            profiles: NewChatStubProfileRepository(),
            explore: NewChatStubExploreRepository(),
            session: NewChatStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )
        await viewModel.prepare()
        let opened = await viewModel.select(ada)
        XCTAssertEqual(opened?.id, ConversationID("dev-dm-ada"))
        XCTAssertEqual(repo.createCallCount, 0)
    }

    private func makeViewModel(
        search: RecordingNewChatSearchRepository,
        messages: CountingNewChatMessageRepository = CountingNewChatMessageRepository(),
        viewerID: ProfileID = ProfileID("viewer-1")
    ) -> NewChatViewModel {
        NewChatViewModel(
            messages: messages,
            search: search,
            profiles: NewChatStubProfileRepository(),
            explore: NewChatStubExploreRepository(),
            session: NewChatStubSession(userID: viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )
    }

    private func sampleProfile(id: String) -> Profile {
        Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: id,
            displayName: id,
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
}

// MARK: - Test doubles

private final class RecordingNewChatSearchRepository: SearchRepository, @unchecked Sendable {
    var delayNanoseconds: UInt64
    private(set) var lastQuery: String?
    private(set) var lastExcluding: ProfileID?

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        lastQuery = query
        lastExcluding = excludingProfileID
        let profileID = ProfileID("\(query)_match")
        return CursorPage(
            items: [
                SearchResult(
                    id: profileID.rawValue,
                    kind: .profile,
                    title: query,
                    subtitle: query,
                    profileID: profileID,
                    tradeID: nil,
                    roomID: nil,
                    postID: nil
                ),
            ],
            nextCursor: nil
        )
    }
}

private final class CountingNewChatMessageRepository: MessageRepository, @unchecked Sendable {
    private(set) var createCallCount = 0
    private var created: [Set<ProfileID>: Conversation] = [:]

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
    }

    func messages(in: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }

    func markRead(conversationID: ConversationID) async throws {}

    func markUnread(conversationID: ConversationID) async throws {}

    func deleteConversation(id: ConversationID) async throws {}

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        let key = Set(participantIDs)
        if let existing = created[key] { return existing }
        createCallCount += 1
        let conversation = Conversation(
            id: ConversationID("dm-\(createCallCount)"),
            participantProfileIDs: participantIDs,
            title: nil,
            peerUsername: nil,
            avatar: nil,
            isGroup: participantIDs.count > 2,
            isPinned: false,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .now
        )
        created[key] = conversation
        return conversation
    }

    func findExistingDirectConversationID(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool {
        false
    }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        try await createConversation(participantIDs: [viewerID, recipient.id])
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        try await createConversation(participantIDs: [viewerID] + recipients.map(\.id))
    }
}

private struct NewChatStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { User(id: UserID("viewer-1"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
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
    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: ProfileID("x"),
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0,
            winRate: 0
        )
    }
    func wallPosts(for: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post {
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
    }
    func followState(from: ProfileID, to: ProfileID) async throws -> FollowState { .none }
    func follow(from: ProfileID, to: ProfileID) async throws {}
    func unfollow(from: ProfileID, to: ProfileID) async throws {}
    func followers(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func following(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func creator(for: ProfileID) async throws -> Creator? { nil }
}

private final class ConfigurableNewChatProfileRepository: ProfileRepository, @unchecked Sendable {
    var followingProfiles: [Profile]

    init(following: [Profile]) {
        followingProfiles = following
    }

    func currentUser() async throws -> User { User(id: UserID("viewer-1"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
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
    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: ProfileID("x"),
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0,
            winRate: 0
        )
    }
    func wallPosts(for: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post {
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
    }
    func followState(from: ProfileID, to: ProfileID) async throws -> FollowState { .none }
    func follow(from: ProfileID, to: ProfileID) async throws {}
    func unfollow(from: ProfileID, to: ProfileID) async throws {}
    func followers(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        guard page.cursor == nil else {
            return CursorPage(items: [], nextCursor: nil)
        }
        return CursorPage(items: followingProfiles, nextCursor: nil)
    }
    func creator(for: ProfileID) async throws -> Creator? { nil }
}

private final class RecordingNewChatExploreRepository: ExploreRepository, @unchecked Sendable {
    let pages: [[Profile]]
    private(set) var discoverCallCount = 0

    init(pages: [[Profile]] = []) {
        self.pages = pages
    }

    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        discoverCallCount += 1
        let index = Int(page.cursor ?? "0") ?? 0
        let items = pages.indices.contains(index) ? pages[index] : []
        let next = index + 1 < pages.count ? String(index + 1) : nil
        return CursorPage(items: items, nextCursor: next)
    }

    func discoverableProfilesWithAvatars(limit: Int) async throws -> [Profile] { [] }
    func socialCounts(for: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int,
        suggestedCursor: String?,
        popularCursor: String?
    ) async throws -> TradeRoomsHomeBootstrap {
        throw AppError.notImplemented(feature: "tradeRoomsHomeBootstrap")
    }
    func discoverRooms(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion] { [] }
    func liveTradersNow(limit: Int) async throws -> [ExploreLiveTraderNow] { [] }
}

private struct NewChatStubExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func socialCounts(for: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct NewChatStubSession: SessionProviding {
    var userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { "token" } }
}
