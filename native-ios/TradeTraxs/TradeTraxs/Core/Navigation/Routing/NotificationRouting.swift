import Foundation

/// Maps push / notification payloads to typed destinations.
protocol NotificationRouting: Sendable {
    func destination(for notification: NotificationDestination) -> AppDestination?
}

/// Production notification → destination mapper.
///
/// Badge ownership stays outside this type (Activity vs Messages).
struct NotificationRouter: NotificationRouting {
    func destination(for notification: NotificationDestination) -> AppDestination? {
        switch notification.category {
        case .directMessage:
            if let conversationID = notification.conversationID {
                return .messages(.thread(conversationID))
            }
            return .tab(.messages)

        case .roomMessage, .roomMention:
            if let roomID = notification.roomID {
                return .feed(.room(roomID))
            }
            return .feed(.rooms)

        case .followRequest:
            return .profile(.followRequests)

        case .tradingReport:
            if let reportID = notification.reportID {
                return .home(.report(reportID))
            }
            return .tab(.home)

        case .activity:
            if let tradeID = notification.tradeID {
                return .home(.tradeDetail(tradeID))
            }
            if let postID = notification.postID {
                return .feed(.post(postID))
            }
            if let reelID = notification.reelID {
                return .feed(.reel(reelID))
            }
            if let profileID = notification.profileID {
                return .feed(.profile(profileID))
            }
            return .profile(.activity)

        case .unknown:
            return .profile(.activity)
        }
    }
}
