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
nonisolated struct NotificationRouter: NotificationRouting {
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

        case .dailyCheckIn:
            return .sheet(.dailyCheckIn)

        case .activity:
            let type = (notification.rawUserInfo["type"] ?? "").lowercased()
            if type == "follow" || type == "follow_request_accepted" {
                if let profileID = notification.profileID {
                    return .feed(.profile(profileID))
                }
                return .profile(.activity)
            }
            if type == "affiliate_referral" || type == "affiliate_commission_earned" {
                return .profile(.affiliate)
            }
            if type == "like" || type == "like_milestone" || type == "like_batch" || type == "comment" {
                if let achievementID = notification.rawUserInfo["achievement_post_id"]
                    ?? notification.rawUserInfo["achievementPostId"]
                    ?? Self.achievementID(from: notification.rawUserInfo["href"])
                {
                    return .feed(.achievement(AchievementID(achievementID)))
                }
                // Social engagement on a trade → SocialTradeDetail (not journal AI).
                if let tradeID = notification.tradeID {
                    return .profile(.trade(tradeID))
                }
            }
            if let tradeID = notification.tradeID {
                return .home(.tradeDetail(tradeID))
            }
            if let postID = notification.postID {
                // Achievement query may have been folded into postID — prefer achievement route when href says so.
                if let achievementID = Self.achievementID(from: notification.rawUserInfo["href"]) {
                    return .feed(.achievement(AchievementID(achievementID)))
                }
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

    private static func achievementID(from href: String?) -> String? {
        guard let href, !href.isEmpty else { return nil }
        let url: URL?
        if href.hasPrefix("http") {
            url = URL(string: href)
        } else if href.hasPrefix("/") {
            url = URL(string: "https://www.tradetraxs.com\(href)")
        } else {
            url = URL(string: href)
        }
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "achievement" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
