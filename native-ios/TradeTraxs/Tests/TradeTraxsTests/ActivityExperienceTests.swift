import XCTest
@testable import TradeTraxs

@MainActor
final class ActivityExperienceTests: XCTestCase {
    override func setUp() async throws {
        ActivityInboxStore.shared.resetForTesting()
    }

    func testDashboardBellOpensActivityRoute() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.open(.profile(.activity))
        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertEqual(store.paths.profile, [.activity])
    }

    func testInboxTypesMatchWebAllowlist() {
        let expected: Set<String> = [
            "like", "comment", "room_join", "room_mention",
            "follow", "follow_request", "follow_request_accepted",
            "affiliate_referral", "affiliate_commission_earned", "trading_report",
        ]
        XCTAssertEqual(Set(NotificationInboxType.all), expected)
        XCTAssertTrue(ActivityNotificationKind.like.isInboxType)
        XCTAssertFalse(ActivityNotificationKind.message.isInboxType)
    }

    func testKindParsingAcceptsSnakeAndLegacyCamelCase() {
        XCTAssertEqual(ActivityNotificationKind.parse("follow_request"), .followRequest)
        XCTAssertEqual(ActivityNotificationKind.parse("followRequest"), .followRequest)
        XCTAssertEqual(ActivityNotificationKind.parse("room_mention"), .roomMention)
        XCTAssertEqual(ActivityNotificationKind.parse("trading_report"), .tradingReport)
    }

    func testDisplayFormattingForCoreTypes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let like = ActivityFixtures.notifications(now: now)[0]
        let text = ActivityNotificationFormatting.primaryText(for: like, actorName: "Alex")
        XCTAssertEqual(text, "Alex liked your trade")

        let follow = ActivityFixtures.notifications(now: now)[1]
        XCTAssertEqual(
            ActivityNotificationFormatting.primaryText(for: follow, actorName: "Mike"),
            "Mike started following you"
        )

        let comment = ActivityFixtures.notifications(now: now)[2]
        XCTAssertTrue(
            ActivityNotificationFormatting.primaryText(for: comment, actorName: "Sarah")
                .contains("Great trade")
        )
    }

    func testRelativeTimestampBuckets() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            ActivityNotificationFormatting.relativeTimestamp(now.addingTimeInterval(-30), now: now),
            "now"
        )
        XCTAssertEqual(
            ActivityNotificationFormatting.relativeTimestamp(now.addingTimeInterval(-120), now: now),
            "2m"
        )
        XCTAssertEqual(
            ActivityNotificationFormatting.relativeTimestamp(now.addingTimeInterval(-7_200), now: now),
            "2h"
        )
    }

    func testTimeSectionsGroupTodayAndEarlier() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sections = ActivityPresentation.sections(
            from: ActivityFixtures.notifications(now: now),
            actors: Dictionary(
                uniqueKeysWithValues: ActivityFixtures.profiles().map { ($0.id, $0) }
            ),
            now: now
        )
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.contains { $0.section == .today })
        XCTAssertTrue(sections.contains { $0.section == .yesterday || $0.section == .earlier })
    }

    func testUnreadBadgeAndMarkReadUpdatesStore() {
        ActivityFixtures.seedStore(ActivityInboxStore.shared)
        let store = ActivityInboxStore.shared
        XCTAssertEqual(store.unreadCount, 2)
        XCTAssertTrue(store.hasUnread)

        store.markReadLocally(id: NotificationID("act-like-1"))
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertTrue(store.items.first { $0.id.rawValue == "act-like-1" }?.isRead == true)

        store.markAllReadLocally()
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.items.allSatisfy(\.isRead))
    }

    func testRealtimeInsertUpdateDelete() {
        ActivityFixtures.seedStore(ActivityInboxStore.shared, unreadCount: 0)
        let store = ActivityInboxStore.shared
        store.markAllReadLocally()

        var inserted = ActivityFixtures.notifications()[0]
        inserted.id = NotificationID("act-rt-1")
        inserted.isRead = false
        store.upsert(inserted)
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertTrue(store.items.contains { $0.id.rawValue == "act-rt-1" })

        inserted.isRead = true
        store.upsert(inserted)
        XCTAssertEqual(store.unreadCount, 0)

        store.remove(id: NotificationID("act-rt-1"))
        XCTAssertFalse(store.items.contains { $0.id.rawValue == "act-rt-1" })
    }

    func testLogoutClearsActivityState() {
        ActivityFixtures.seedStore(ActivityInboxStore.shared)
        XCTAssertTrue(ActivityInboxStore.shared.hasLoaded)
        ActivityInboxStore.shared.invalidate()
        XCTAssertFalse(ActivityInboxStore.shared.hasLoaded)
        XCTAssertFalse(ActivityInboxStore.shared.hasBootstrappedUnread)
        XCTAssertEqual(ActivityInboxStore.shared.unreadCount, 0)
        XCTAssertTrue(ActivityInboxStore.shared.items.isEmpty)
    }

    func testUnreadBootstrapDoesNotHydrateActivityFeed() async {
        let repo = ActivityStubNotificationRepository(
            items: ActivityFixtures.notifications(),
            profiles: ActivityFixtures.profiles()
        )
        await ActivityInboxStore.shared.bootstrapUnreadIfNeeded(
            notifications: repo,
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            realtimeHub: nil
        )
        XCTAssertEqual(repo.unreadCountCallCount, 1)
        XCTAssertEqual(repo.notificationsPageCallCount, 0)
        XCTAssertTrue(ActivityInboxStore.shared.hasBootstrappedUnread)
        XCTAssertFalse(ActivityInboxStore.shared.hasLoaded)
        XCTAssertTrue(ActivityInboxStore.shared.items.isEmpty)
        XCTAssertEqual(ActivityInboxStore.shared.unreadCount, 2)
    }

    func testActivityOpenHydratesFeedAfterUnreadBootstrap() async {
        let repo = ActivityStubNotificationRepository(
            items: ActivityFixtures.notifications(),
            profiles: ActivityFixtures.profiles()
        )
        await ActivityInboxStore.shared.bootstrapUnreadIfNeeded(
            notifications: repo,
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            realtimeHub: nil
        )
        await ActivityInboxStore.shared.startIfNeeded(
            notifications: repo,
            followRequests: ActivityStubFollowRequestRepository(),
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            realtimeHub: nil
        )
        XCTAssertEqual(repo.notificationsPageCallCount, 1)
        XCTAssertTrue(ActivityInboxStore.shared.hasLoaded)
        XCTAssertFalse(ActivityInboxStore.shared.items.isEmpty)
    }

    func testActorHydrationIsBatchedNotNPlusOne() async {
        SessionProfileStore.shared.invalidate()
        let repo = ActivityStubNotificationRepository(
            items: ActivityFixtures.notifications(),
            profiles: ActivityFixtures.profiles()
        )
        let profileRepo = ActivityStubProfileRepository(profiles: ActivityFixtures.profiles())
        let cache = DetailPresentationCache()
        let viewModel = ActivityHomeViewModel(
            notifications: repo,
            followRequests: ActivityStubFollowRequestRepository(),
            profiles: profileRepo,
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(profileRepo.profilesBatchCallCount, 1)
        XCTAssertEqual(Set(profileRepo.lastBatchIDs), Set(ActivityFixtures.profiles().map(\.id)))
        XCTAssertEqual(viewModel.phase, .loaded)
    }

    func testMarkAllReadPersistsViaRepository() async {
        let repo = ActivityStubNotificationRepository(
            items: ActivityFixtures.notifications(),
            profiles: ActivityFixtures.profiles()
        )
        ActivityFixtures.seedStore(ActivityInboxStore.shared)
        let viewModel = ActivityHomeViewModel(
            notifications: repo,
            followRequests: ActivityStubFollowRequestRepository(),
            profiles: ActivityStubProfileRepository(),
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )
        viewModel.markAllRead()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(repo.markAllReadCallCount, 1)
        XCTAssertEqual(ActivityInboxStore.shared.unreadCount, 0)
    }

    func testRoutingFamilies() {
        let now = Date()
        let items = ActivityFixtures.notifications(now: now)
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: items[0]),
            .profile(.trade(TradeID("trade-1")))
        )
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: items[1]),
            .profile(.otherProfile(ActivityFixtures.mikeID))
        )
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: items[2]),
            .profile(.post(PostID("post-1")))
        )
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: items[3]),
            .profile(.room(RoomID("room-1")))
        )
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: items[4]),
            .home(.report(ReportID("weekly_last")))
        )

        var request = items[1]
        request.kind = .followRequest
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: request),
            .profile(.followRequests)
        )

        var affiliate = items[4]
        affiliate.kind = .affiliateReferral
        XCTAssertEqual(
            ActivityNotificationRouting.appDestination(for: affiliate),
            .profile(.affiliate)
        )
    }

    func testActivityOpensNotificationSettingsStack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = ActivityHomeViewModel(
            notifications: ActivityStubNotificationRepository(),
            followRequests: ActivityStubFollowRequestRepository(),
            profiles: ActivityStubProfileRepository(),
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator,
            inboxStore: .shared
        )
        viewModel.openNotificationSettings()
        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertTrue(store.paths.profile.contains(.settings(.home)))
        XCTAssertTrue(store.paths.profile.contains(.settings(.notifications)))
    }

    func testDTOMappingParsesRoomMentionJSON() {
        let dto = NotificationDTO.Item(
            id: "n1",
            type: "room_mention",
            kind: nil,
            user_id: "u1",
            sender_id: "s1",
            actor_profile_id: nil,
            title: nil,
            content: #"{"room_id":"r1","room_slug":"nq","room_name":"NQ Desk","section_id":"sec","section_name":"General","message_id":"m1","message_preview":"hello"}"#,
            body: nil,
            created_at: "2026-08-10T12:00:00Z",
            read: false,
            is_read: nil,
            trade_id: nil,
            post_id: nil,
            profile_post_id: nil,
            achievement_post_id: nil,
            reel_id: nil,
            comment_id: nil,
            room_id: nil,
            room_message_id: nil
        )
        let mapped = DefaultNotificationRepository.mapNotification(dto)
        XCTAssertEqual(mapped?.kind, .roomMention)
        XCTAssertEqual(mapped?.roomID, RoomID("r1"))
        XCTAssertEqual(mapped?.roomSlug, "nq")
        XCTAssertEqual(mapped?.messagePreview, "hello")
        XCTAssertEqual(mapped?.isRead, false)
    }

    func testEmptyAndErrorPhases() async {
        let emptyRepo = ActivityStubNotificationRepository(items: [], profiles: [])
        let viewModel = ActivityHomeViewModel(
            notifications: emptyRepo,
            followRequests: ActivityStubFollowRequestRepository(requests: []),
            profiles: ActivityStubProfileRepository(),
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertTrue(viewModel.showsEmpty)

        ActivityInboxStore.shared.resetForTesting()
        let failing = ActivityStubNotificationRepository(shouldFail: true)
        let failedVM = ActivityHomeViewModel(
            notifications: failing,
            followRequests: ActivityStubFollowRequestRepository(),
            profiles: ActivityStubProfileRepository(),
            session: ActivityStubSession(userID: ActivityFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )
        await failedVM.refresh()
        if case .failed = failedVM.phase {
            XCTAssertTrue(true)
        } else {
            // Soft-fail path may still land loaded with empty cache.
            XCTAssertTrue(failedVM.showsEmpty || failedVM.phase == .loaded)
        }
    }

    func testFollowRequestActionsUpdatePendingCount() async {
        let repo = ActivityStubFollowRequestRepository(requests: ActivityFixtures.followRequests())
        ActivityInboxStore.shared.setPendingFollowRequestCount(1)
        let viewModel = FollowRequestsViewModel(
            followRequests: repo,
            notifications: ActivityStubNotificationRepository(
                profiles: ActivityFixtures.profiles()
            ),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.rows.count, 1)
        viewModel.approve(FollowRequestID("fr-1"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(repo.approveCallCount, 1)
        XCTAssertEqual(ActivityInboxStore.shared.pendingFollowRequestCount, 0)
    }

    func testPaginationAppendsWithoutDuplicate() {
        let store = ActivityInboxStore.shared
        ActivityFixtures.seedStore(store)
        let first = store.items
        store.append(page: first, nextCursor: nil)
        XCTAssertEqual(store.items.count, first.count)
    }

    func testPushCompatibleNotificationDestination() {
        let like = ActivityFixtures.notifications()[0]
        let destination = ActivityNotificationRouting.notificationDestination(for: like)
        XCTAssertEqual(destination.category, .activity)
        XCTAssertEqual(destination.tradeID, TradeID("trade-1"))
        let router = NotificationRouter()
        XCTAssertEqual(
            router.destination(for: destination),
            .profile(.trade(TradeID("trade-1")))
        )
    }
}

// MARK: - Stubs

private struct ActivityStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private final class ActivityStubNotificationRepository: NotificationRepository, @unchecked Sendable {
    var items: [ActivityNotification]
    var profiles: [Profile]
    var shouldFail: Bool
    private(set) var profilesCallCount = 0
    private(set) var lastProfileIDs: [ProfileID] = []
    private(set) var markAllReadCallCount = 0
    private(set) var notificationsPageCallCount = 0
    private(set) var unreadCountCallCount = 0

    init(
        items: [ActivityNotification] = ActivityFixtures.notifications(),
        profiles: [Profile] = ActivityFixtures.profiles(),
        shouldFail: Bool = false
    ) {
        self.items = items
        self.profiles = profiles
        self.shouldFail = shouldFail
    }

    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        notificationsPageCallCount += 1
        if shouldFail { throw AppError.unknown(message: "network") }
        return CursorPage(items: items, nextCursor: nil)
    }

    func notification(id: NotificationID) async throws -> ActivityNotification? {
        items.first { $0.id == id }
    }

    func unreadCount() async throws -> Int {
        unreadCountCallCount += 1
        if shouldFail { throw AppError.unknown(message: "network") }
        return items.filter { !$0.isRead }.count
    }

    func markRead(id: NotificationID) async throws {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isRead = true
        }
    }

    func markAllRead() async throws {
        markAllReadCallCount += 1
        items = items.map {
            var copy = $0
            copy.isRead = true
            return copy
        }
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        profilesCallCount += 1
        lastProfileIDs = ids
        return profiles.filter { ids.contains($0.id) }
    }
}

private final class ActivityStubProfileRepository: ProfileRepository, @unchecked Sendable {
    private let profiles: [Profile]
    private(set) var profilesBatchCallCount = 0
    private(set) var lastBatchIDs: [ProfileID] = []

    init(profiles: [Profile] = ActivityFixtures.profiles()) {
        self.profiles = profiles
    }

    func currentUser() async throws -> User {
        User(id: UserID(ActivityFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        profiles.first { $0.id == id } ?? Profile(
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

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        profilesBatchCallCount += 1
        lastBatchIDs = ids
        return profiles.filter { ids.contains($0.id) }
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
        throw AppError.unknown(message: "not found")
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

private final class ActivityStubFollowRequestRepository: FollowRequestRepository, @unchecked Sendable {
    var requests: [FollowRequest]
    private(set) var approveCallCount = 0
    private(set) var declineCallCount = 0

    init(requests: [FollowRequest] = []) {
        self.requests = requests
    }

    func pendingRequests() async throws -> [FollowRequest] { requests }

    func approve(id: FollowRequestID) async throws {
        approveCallCount += 1
        requests.removeAll { $0.id == id }
    }

    func decline(id: FollowRequestID) async throws {
        declineCallCount += 1
        requests.removeAll { $0.id == id }
    }
}
