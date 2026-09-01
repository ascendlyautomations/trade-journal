import Foundation

enum ActivityFixtures {
    static let viewerID = ProfileID("dev.activity.viewer")
    static let alexID = ProfileID("dev.activity.alex")
    static let mikeID = ProfileID("dev.activity.mike")
    static let sarahID = ProfileID("dev.activity.sarah")

    static func profiles() -> [Profile] {
        [
            makeProfile(id: alexID, username: "alex", name: "Alex"),
            makeProfile(id: mikeID, username: "mike", name: "Mike"),
            makeProfile(id: sarahID, username: "sarah", name: "Sarah"),
        ]
    }

    static func notifications(now: Date = .now) -> [ActivityNotification] {
        [
            ActivityNotification(
                id: NotificationID("act-like-1"),
                kind: .like,
                actorProfileID: alexID,
                title: "like",
                body: "",
                tradeID: TradeID("trade-1"),
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
                createdAt: now.addingTimeInterval(-120),
                isRead: false
            ),
            ActivityNotification(
                id: NotificationID("act-follow-1"),
                kind: .follow,
                actorProfileID: mikeID,
                title: "follow",
                body: "",
                tradeID: nil,
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
                createdAt: now.addingTimeInterval(-3_600),
                isRead: false
            ),
            ActivityNotification(
                id: NotificationID("act-comment-1"),
                kind: .comment,
                actorProfileID: sarahID,
                title: "comment",
                body: "Great trade setup",
                tradeID: nil,
                postID: PostID("post-1"),
                profilePostID: nil,
                achievementPostID: nil,
                reelID: nil,
                commentID: CommentID("comment-1"),
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
                createdAt: now.addingTimeInterval(-10_800),
                isRead: true
            ),
            ActivityNotification(
                id: NotificationID("act-mention-1"),
                kind: .roomMention,
                actorProfileID: alexID,
                title: "room_mention",
                body: "",
                tradeID: nil,
                postID: nil,
                profilePostID: nil,
                achievementPostID: nil,
                reelID: nil,
                commentID: nil,
                conversationID: nil,
                roomID: RoomID("room-1"),
                roomMessageID: RoomMessageID("rm-1"),
                followRequestID: nil,
                roomSlug: "futures-traders",
                roomName: "Futures Traders",
                sectionID: "general",
                sectionName: "General",
                messagePreview: "check this NQ level",
                reportID: nil,
                affiliateHref: nil,
                isReply: false,
                isMention: true,
                createdAt: now.addingTimeInterval(-90_000),
                isRead: true
            ),
            ActivityNotification(
                id: NotificationID("act-report-1"),
                kind: .tradingReport,
                actorProfileID: nil,
                title: "Weekly trading report",
                body: "Your weekly summary is ready",
                tradeID: nil,
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
                reportID: ReportID("weekly_last"),
                affiliateHref: nil,
                isReply: false,
                isMention: false,
                createdAt: now.addingTimeInterval(-200_000),
                isRead: true
            ),
        ]
    }

    static func followRequests(now: Date = .now) -> [FollowRequest] {
        [
            FollowRequest(
                id: FollowRequestID("fr-1"),
                requesterProfileID: alexID,
                createdAt: now.addingTimeInterval(-600)
            ),
        ]
    }

    @MainActor
    static func seedStore(
        _ store: ActivityInboxStore,
        now: Date = .now,
        unreadCount: Int? = nil
    ) {
        let items = notifications(now: now)
        store.replace(
            items: items,
            unreadCount: unreadCount ?? items.filter { !$0.isRead }.count,
            nextCursor: nil,
            pendingFollowRequestCount: followRequests(now: now).count
        )
    }

    private static func makeProfile(id: ProfileID, username: String, name: String) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
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
