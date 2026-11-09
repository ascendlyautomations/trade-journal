import XCTest
@testable import TradeTraxs

/// External notification and deep-link entry replaces an existing visit instead of stacking it.
@MainActor
final class ExternalNavigationTests: XCTestCase {
    private let room = RoomID("room-1")
    private let slug = RoomID("futures-desk")
    private let uuid = RoomID("11111111-1111-1111-1111-111111111111")

    override func setUp() {
        super.setUp()
        RoomNavigationFocusStore.shared.clear()
    }

    override func tearDown() {
        RoomNavigationFocusStore.shared.clear()
        super.tearDown()
    }

    func testRepeatedRoomOpenRefreshesWithoutStacking() {
        let (coordinator, store) = makeHarness()

        coordinator.openExternal(.messages(.room(room)))
        coordinator.openExternal(.messages(.room(room)))

        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.paths.messages, [.room(room)])
        XCTAssertEqual(store.externalDestinationEpochs["room:\(room.rawValue)"], 2)
        XCTAssertTrue(store.paths.home.isEmpty)
        XCTAssertTrue(store.paths.feed.isEmpty)
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    func testRoomVisitTailIsRemovedAndEarlierScreenStays() {
        let (coordinator, store) = makeHarness()
        let conversation = ConversationID("dm-1")
        store.paths.messages = [.thread(conversation), .room(room), .roomInfo(room)]

        coordinator.openExternal(.messages(.room(room)))

        XCTAssertEqual(store.paths.messages, [.thread(conversation), .room(room)])
        XCTAssertEqual(store.externalDestinationEpochs["room:\(room.rawValue)"], 1)
    }

    func testSlugAndUUIDResolveToOneRoomAcrossTabs() {
        let (coordinator, store) = makeHarness()
        RoomNavigationFocusStore.shared.registerRoomAlias([slug, uuid])
        store.paths.messages = [.room(slug), .roomMembers(slug)]
        store.paths.profile = [.otherProfile(ProfileID("host")), .room(uuid)]

        coordinator.openExternal(.messages(.room(uuid)))

        XCTAssertEqual(store.paths.messages, [.room(uuid)])
        XCTAssertEqual(store.paths.profile, [.otherProfile(ProfileID("host"))])
        XCTAssertEqual(store.externalDestinationEpochs["room:\(uuid.rawValue)"], 1)
        XCTAssertEqual(store.externalDestinationEpochs["room:\(slug.rawValue)"], 1)
    }

    func testRepeatedRoomMentionDifferentSubRoomsBumpsEpochAndReseedsFocus() {
        let (coordinator, store) = makeHarness()
        let facade = NotificationRouterFacade(router: NotificationRouter())
        store.paths.messages = [.room(room)]

        let generalMention = NotificationDestination(
            category: .roomMention,
            threadID: "msg-general",
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: room,
            reportID: nil,
            sectionID: "general",
            messageID: "msg-general",
            rawUserInfo: ["type": "room_mention"]
        )
        XCTAssertTrue(facade.route(generalMention, using: coordinator, store: store))
        XCTAssertEqual(store.externalDestinationEpochs["room:\(room.rawValue)"], 1)

        let tradesMention = NotificationDestination(
            category: .roomMention,
            threadID: "msg-trades",
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: room,
            reportID: nil,
            sectionID: "trades",
            messageID: "msg-trades",
            rawUserInfo: ["type": "room_mention"]
        )
        XCTAssertTrue(facade.route(tradesMention, using: coordinator, store: store))
        XCTAssertEqual(store.paths.messages, [.room(room)])
        XCTAssertEqual(store.externalDestinationEpochs["room:\(room.rawValue)"], 2)
        XCTAssertEqual(store.externalRoomFocusTokens["room:\(room.rawValue)"], "c:trades&m:msg-trades")
        let focus = RoomNavigationFocusStore.shared.consume(for: room)
        XCTAssertEqual(focus?.channelID, RoomChannelID("trades"))
        XCTAssertEqual(focus?.messageID, MessageID("msg-trades"))
    }

    func testNotificationFacadeReconcilesSlugAliasAndKeepsFocus() {
        let (coordinator, store) = makeHarness()
        store.paths.messages = [.room(slug), .roomInfo(slug)]
        let facade = NotificationRouterFacade(router: NotificationRouter())
        let notification = NotificationDestination(
            category: .roomMention,
            threadID: "msg-9",
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: uuid,
            reportID: nil,
            sectionID: "general",
            messageID: "msg-9",
            rawUserInfo: [
                "type": "room_mention",
                "room_slug": slug.rawValue,
            ]
        )

        XCTAssertTrue(facade.route(notification, using: coordinator, store: store))

        XCTAssertEqual(store.paths.messages, [.room(uuid)])
        let focus = RoomNavigationFocusStore.shared.consume(for: slug, resolvedRoomID: uuid)
        XCTAssertEqual(focus?.messageID, MessageID("msg-9"))
        XCTAssertEqual(focus?.channelID, RoomChannelID("general"))
        XCTAssertNil(RoomNavigationFocusStore.shared.consume(for: uuid))
    }

    func testColdStartPendingRoomReplacesRestoredVisit() {
        let store = NavigationStore()
        store.sessionPhase = .unauthenticated
        store.pendingAfterAuth = PendingDestination(destination: .messages(.room(room)))
        let coordinator = NavigationCoordinator(store: store)
        var snapshot = NavigationState.initial
        snapshot.sessionPhase = .authenticated
        snapshot.selectedTab = .feed
        snapshot.homePath = [.trades]
        snapshot.messagesPath = [.thread(ConversationID("dm-1")), .room(room), .roomSettings(room)]

        coordinator.markAuthenticated(applyingDeferred: snapshot)

        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(
            store.paths.messages,
            [.thread(ConversationID("dm-1")), .room(room)]
        )
        XCTAssertEqual(store.paths.home, [.trades])
        XCTAssertNil(store.pendingAfterAuth)
        XCTAssertEqual(store.externalDestinationEpochs["room:\(room.rawValue)"], 1)
    }

    func testFeedPostAndProfileTradeRemoveDuplicatesOnOtherTabs() {
        let (coordinator, store) = makeHarness()
        let post = PostID("post-1")
        let trade = TradeID("trade-1")
        store.paths.feed = [.post(post), .profile(ProfileID("author"))]
        store.paths.messages = [.sharedPost(post)]
        store.paths.home = [.socialTrade(trade), .post(post)]
        store.paths.profile = [.activity, .trade(trade)]

        coordinator.openExternal(.feed(.post(post)))

        XCTAssertEqual(store.selectedTab, .feed)
        XCTAssertEqual(store.paths.feed, [.post(post)])
        XCTAssertTrue(store.paths.messages.isEmpty)
        XCTAssertEqual(store.paths.home, [.socialTrade(trade)])
        XCTAssertEqual(store.externalDestinationEpochs["post:\(post.rawValue)"], 1)

        coordinator.openExternal(.profile(.trade(trade)))

        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertEqual(store.paths.profile, [.activity, .trade(trade)])
        XCTAssertTrue(store.paths.home.isEmpty)
        XCTAssertEqual(store.paths.feed, [.post(post)])
        XCTAssertEqual(store.externalDestinationEpochs["trade:\(trade.rawValue)"], 1)
    }

    func testDirectMessageAchievementAndReelRefreshInPlace() {
        let (coordinator, store) = makeHarness()
        let conversation = ConversationID("dm-7")
        let achievement = AchievementID("ach-1")
        let reel = ReelID("reel-1")

        store.paths.messages = [.thread(conversation), .profile(ProfileID("peer"))]
        coordinator.openExternal(.messages(.thread(conversation)))
        coordinator.openExternal(.messages(.thread(conversation)))
        XCTAssertEqual(store.paths.messages, [.thread(conversation)])
        XCTAssertEqual(store.externalDestinationEpochs["thread:\(conversation.rawValue)"], 2)

        store.paths.feed = [.achievement(achievement), .profile(ProfileID("author"))]
        store.paths.profile = [.achievement(achievement)]
        coordinator.openExternal(.feed(.achievement(achievement)))
        XCTAssertEqual(store.paths.feed, [.achievement(achievement)])
        XCTAssertTrue(store.paths.profile.isEmpty)

        store.paths.home = [.reel(reel)]
        coordinator.openExternal(.feed(.reel(reel)))
        XCTAssertEqual(store.paths.feed, [.achievement(achievement), .reel(reel)])
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    func testExternalOpenDismissesNavigationPresentations() {
        let (coordinator, store) = makeHarness()
        store.presentedSheet = .dailyCheckIn
        store.presentedFullScreen = .newPost

        coordinator.openExternal(.messages(.room(room)))

        XCTAssertNil(store.presentedSheet)
        XCTAssertNil(store.presentedFullScreen)
        XCTAssertEqual(store.paths.messages, [.room(room)])
    }

    func testInAppPushesAndActivityRowsStillAppend() {
        let (coordinator, store) = makeHarness()

        coordinator.pushMessages(.room(room))
        coordinator.pushMessages(.room(room))
        XCTAssertEqual(store.paths.messages, [.room(room), .room(room)])

        store.paths.home = [.activity]
        ActivityNotificationRouting.open(
            makeRoomMention(),
            host: .home,
            coordinator: coordinator
        )
        XCTAssertEqual(store.paths.home, [.activity, .room(room)])
        XCTAssertEqual(store.selectedTab, .home)
    }

    func testLoggedOutExternalOpenStaysPending() {
        let store = NavigationStore()
        store.sessionPhase = .unauthenticated
        let coordinator = NavigationCoordinator(store: store)

        coordinator.openExternal(.messages(.room(room)))

        XCTAssertTrue(store.paths.messages.isEmpty)
        XCTAssertEqual(store.pendingAfterAuth?.asAppDestination, .messages(.room(room)))
    }

    private func makeHarness() -> (NavigationCoordinator, NavigationStore) {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        return (NavigationCoordinator(store: store), store)
    }

    private func makeRoomMention() -> ActivityNotification {
        ActivityNotification(
            id: NotificationID("mention-1"),
            kind: .roomMention,
            actorProfileID: ProfileID("alex"),
            title: "Mention",
            body: "",
            tradeID: nil,
            postID: nil,
            profilePostID: nil,
            achievementPostID: nil,
            reelID: nil,
            commentID: nil,
            conversationID: nil,
            roomID: room,
            roomMessageID: nil,
            followRequestID: nil,
            joinRequestID: nil,
            joinRequestStatus: nil,
            roomSlug: nil,
            roomName: "Futures",
            sectionID: nil,
            sectionName: nil,
            messagePreview: nil,
            reportID: nil,
            affiliateHref: nil,
            isReply: false,
            isMention: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false
        )
    }
}
