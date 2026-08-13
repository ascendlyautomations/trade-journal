import XCTest
@testable import TradeTraxs

@MainActor
final class PushNotificationExperienceTests: XCTestCase {
    func testPayloadParserMapsDM() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "message",
            "href": "/messages/convo-1",
            "conversationId": "convo-1",
            "aps": ["badge": 3],
        ])
        XCTAssertEqual(destination.category, .directMessage)
        XCTAssertEqual(destination.conversationID, ConversationID("convo-1"))
        XCTAssertEqual(PushNotificationPayloadParser.badgeValue(from: [
            "aps": ["badge": 3],
        ]), 3)
    }

    func testPayloadParserMapsTradeRoomWithSectionAndMessage() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "room_mention",
            "href": "/community?room=futures-lounge&section=sec-gold&message=msg-9",
            "roomId": "room-uuid-1",
            "roomSlug": "futures-lounge",
        ])
        XCTAssertEqual(destination.category, .roomMention)
        XCTAssertEqual(destination.roomID, RoomID("room-uuid-1"))
        XCTAssertEqual(destination.sectionID, "sec-gold")
        XCTAssertEqual(destination.messageID, "msg-9")
    }

    func testPayloadParserMapsTradeLike() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "like",
            "href": "/trade/trade-22",
            "trade_id": "trade-22",
        ])
        XCTAssertEqual(destination.category, .activity)
        XCTAssertEqual(destination.tradeID, TradeID("trade-22"))
        let routed = NotificationRouter().destination(for: destination)
        XCTAssertEqual(routed, .home(.tradeDetail(TradeID("trade-22"))))
    }

    func testNotificationRouterMapsRoomToMessagesTab() {
        let destination = NotificationDestination(
            category: .roomMessage,
            threadID: "msg-1",
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: RoomID("room-1"),
            reportID: nil,
            sectionID: "general",
            messageID: "msg-1",
            rawUserInfo: ["type": "room_message"]
        )
        XCTAssertEqual(
            NotificationRouter().destination(for: destination),
            .messages(.room(RoomID("room-1")))
        )
    }

    func testFollowsNeverGroup() {
        let now = Date()
        let follows = [
            makeNotification(id: "f1", kind: .follow, actor: "a1", createdAt: now),
            makeNotification(id: "f2", kind: .follow, actor: "a2", createdAt: now.addingTimeInterval(-10)),
        ]
        let grouped = ActivityNotificationGrouping.group(follows, actors: [:])
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.map(\.notificationIDs.count), [1, 1])
    }

    func testLikesGroupPerTrade() {
        let now = Date()
        let likes = [
            makeNotification(
                id: "l1",
                kind: .like,
                actor: "nick",
                tradeID: "trade-1",
                createdAt: now
            ),
            makeNotification(
                id: "l2",
                kind: .like,
                actor: "john",
                tradeID: "trade-1",
                createdAt: now.addingTimeInterval(-5)
            ),
            makeNotification(
                id: "l3",
                kind: .like,
                actor: "mike",
                tradeID: "trade-2",
                createdAt: now.addingTimeInterval(-6)
            ),
        ]
        let actors: [ProfileID: Profile] = [
            ProfileID("nick"): makeProfile(id: "nick", name: "Nick"),
            ProfileID("john"): makeProfile(id: "john", name: "John"),
            ProfileID("mike"): makeProfile(id: "mike", name: "Mike"),
        ]
        let grouped = ActivityNotificationGrouping.group(likes, actors: actors)
        XCTAssertEqual(grouped.count, 2)
        let trade1 = grouped.first { $0.notification.tradeID == TradeID("trade-1") }
        XCTAssertEqual(trade1?.notificationIDs.count, 2)
        XCTAssertTrue(trade1?.primaryText.contains("liked your trade") == true)
        XCTAssertTrue(trade1?.primaryText.contains("Nick") == true)
    }

    func testMentionsAndRepliesStayIndividual() {
        let now = Date()
        var reply = makeNotification(
            id: "c1",
            kind: .comment,
            actor: "a",
            tradeID: "trade-1",
            createdAt: now
        )
        reply.isReply = true
        var mention = makeNotification(
            id: "c2",
            kind: .comment,
            actor: "b",
            tradeID: "trade-1",
            createdAt: now.addingTimeInterval(-1)
        )
        mention.isMention = true
        let normal = makeNotification(
            id: "c3",
            kind: .comment,
            actor: "c",
            tradeID: "trade-1",
            createdAt: now.addingTimeInterval(-2)
        )
        let grouped = ActivityNotificationGrouping.group([reply, mention, normal], actors: [:])
        XCTAssertEqual(grouped.count, 3)
    }

    func testDMCollapseCopy() {
        XCTAssertEqual(
            PushNotificationGrouping.dmCollapseBody(senderName: "John", count: 3),
            "John sent 3 messages"
        )
        XCTAssertEqual(
            PushNotificationGrouping.roomChannelLabel(roomName: "Futures Lounge", sectionName: "gold"),
            "Futures Lounge • #gold"
        )
    }

    func testRoomFocusStoreConsumeOnce() {
        RoomNavigationFocusStore.shared.clear()
        RoomNavigationFocusStore.shared.seed(
            roomID: RoomID("room-1"),
            sectionID: "general",
            messageID: "msg-1"
        )
        let first = RoomNavigationFocusStore.shared.consume(for: RoomID("room-1"))
        let second = RoomNavigationFocusStore.shared.consume(for: RoomID("room-1"))
        XCTAssertEqual(first?.channelID, RoomChannelID("general"))
        XCTAssertEqual(first?.messageID, MessageID("msg-1"))
        XCTAssertNil(second)
    }

    func testForegroundPolicySilencesLikes() {
        let like = NotificationDestination(
            category: .activity,
            threadID: nil,
            tradeID: TradeID("t1"),
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: nil,
            reportID: nil,
            rawUserInfo: ["type": "like"]
        )
        XCTAssertEqual(PushNotificationPresentationPolicy.priority(for: like), .silent)
        let mention = NotificationDestination(
            category: .roomMention,
            threadID: "m1",
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: RoomID("r1"),
            reportID: nil,
            rawUserInfo: ["type": "room_mention"]
        )
        XCTAssertEqual(PushNotificationPresentationPolicy.priority(for: mention), .high)
    }

    // MARK: - Helpers

    private func makeNotification(
        id: String,
        kind: ActivityNotificationKind,
        actor: String,
        tradeID: String? = nil,
        createdAt: Date
    ) -> ActivityNotification {
        ActivityNotification(
            id: NotificationID(id),
            kind: kind,
            actorProfileID: ProfileID(actor),
            title: kind.rawValue,
            body: "",
            tradeID: tradeID.map { TradeID($0) },
            postID: nil,
            profilePostID: nil,
            achievementPostID: nil,
            reelID: nil,
            commentID: nil,
            conversationID: nil,
            roomID: nil,
            roomMessageID: nil,
            followRequestID: nil,
            roomSlug: nil,
            roomName: nil,
            sectionID: nil,
            sectionName: nil,
            messagePreview: nil,
            reportID: nil,
            affiliateHref: nil,
            isReply: false,
            isMention: false,
            createdAt: createdAt,
            isRead: false
        )
    }

    private func makeProfile(id: String, name: String) -> Profile {
        Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: id,
            displayName: name,
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
