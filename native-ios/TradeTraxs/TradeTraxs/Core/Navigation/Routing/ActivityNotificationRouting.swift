import Foundation

/// Maps an Activity row → ``NotificationDestination`` / ``AppDestination``.
///
/// Push / deep-link paths continue to use ``NotificationRouter``. Activity row taps
/// prefer Profile-stack destinations so Back returns to Activity.
enum ActivityNotificationRouting {
    static func notificationDestination(
        for notification: ActivityNotification
    ) -> NotificationDestination {
        switch notification.kind {
        case .followRequest:
            return NotificationDestination(
                category: .followRequest,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .roomJoin, .roomMention:
            return NotificationDestination(
                category: .roomMention,
                threadID: notification.roomMessageID?.rawValue,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: nil,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "room_slug": notification.roomSlug ?? "",
                ]
            )

        case .tradingReport:
            return NotificationDestination(
                category: .tradingReport,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: nil,
                roomID: nil,
                reportID: notification.reportID,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .follow, .followRequestAccepted:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .like, .comment:
            let postID = notification.postID
                ?? notification.profilePostID
                ?? notification.achievementPostID
            return NotificationDestination(
                category: .activity,
                threadID: notification.commentID?.rawValue,
                tradeID: notification.tradeID,
                postID: postID,
                reelID: notification.reelID,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .affiliateReferral, .affiliateCommissionEarned:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "href": notification.affiliateHref ?? "/affiliate/dashboard",
                ]
            )

        case .message:
            return NotificationDestination(
                category: .directMessage,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: notification.conversationID,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": "message"]
            )

        case .system:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: notification.tradeID,
                postID: notification.postID,
                reelID: notification.reelID,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: notification.reportID,
                rawUserInfo: ["type": "system"]
            )
        }
    }

    /// Activity-local destination resolution (keeps Profile stack when possible).
    static func appDestination(
        for notification: ActivityNotification,
        router: any NotificationRouting = NotificationRouter()
    ) -> AppDestination {
        switch notification.kind {
        case .followRequest:
            return .profile(.followRequests)

        case .follow, .followRequestAccepted:
            if let profileID = notification.actorProfileID {
                return .profile(.otherProfile(profileID))
            }
            return .profile(.activity)

        case .like, .comment:
            if let reelID = notification.reelID {
                return .profile(.reel(reelID))
            }
            if let achievementPostID = notification.achievementPostID {
                return .profile(.post(achievementPostID))
            }
            if let postID = notification.postID ?? notification.profilePostID {
                return .profile(.post(postID))
            }
            if let tradeID = notification.tradeID {
                return .profile(.trade(tradeID))
            }
            if let profileID = notification.actorProfileID {
                return .profile(.otherProfile(profileID))
            }
            return .profile(.activity)

        case .roomJoin, .roomMention:
            if let roomID = notification.roomID {
                return .profile(.room(roomID))
            }
            return .profile(.rooms)

        case .tradingReport:
            if let reportID = notification.reportID {
                return .home(.report(reportID))
            }
            return .tab(.home)

        case .affiliateReferral, .affiliateCommissionEarned:
            return .profile(.affiliate)

        case .message:
            return router.destination(for: notificationDestination(for: notification))
                ?? .tab(.messages)

        case .system:
            return router.destination(for: notificationDestination(for: notification))
                ?? .profile(.activity)
        }
    }
}
