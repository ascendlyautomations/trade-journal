import Foundation

/// Maps push / notification payloads to typed destinations.
protocol NotificationRouting: Sendable {
    func destination(for notification: NotificationDestination) -> AppDestination?
}

/// Production notification → destination mapper.
///
/// Badge ownership stays outside this type (Activity vs Messages).
/// Room channel / message highlight is seeded by ``NotificationRouterFacade`` via
/// ``RoomNavigationFocusStore`` before ``open``.
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
                // Messages tab owns Trade Room threads opened from push.
                return .messages(.room(roomID))
            }
            return .tab(.messages)

        case .followRequest:
            return .profile(.followRequests)

        case .tradingReport:
            if let reportID = notification.reportID {
                return .home(.report(reportID))
            }
            return .tab(.home)

        case .activity:
            let type = (notification.rawUserInfo["type"] ?? "").lowercased()
            if type == "follow" || type == "follow_request_accepted" {
                if let profileID = notification.profileID {
                    return .feed(.profile(profileID))
                }
                return .profile(.activity)
            }
            if let tradeID = notification.tradeID {
                return .home(.tradeDetail(tradeID))
            }
            if let postID = notification.postID {
                return .feed(.post(postID))
            }
            if let reelID = notification.reelID {
                return .feed(.reel(reelID))
            }
            if let href = notification.rawUserInfo["href"],
               let url = URL(string: href.hasPrefix("/") ? "https://www.tradetraxs.com\(href)" : href),
               let deep = DeepLinkParser().parse(url: url)
            {
                return deep
            }
            if let profileID = notification.profileID {
                return .feed(.profile(profileID))
            }
            return .profile(.activity)

        case .unknown:
            if let href = notification.rawUserInfo["href"],
               let url = URL(string: href.hasPrefix("/") ? "https://www.tradetraxs.com\(href)" : href),
               let deep = DeepLinkParser().parse(url: url)
            {
                return deep
            }
            return .profile(.activity)
        }
    }
}
