import Foundation

/// Logical identity for notification and universal-link destinations.
///
/// Room channel, info, members, and settings screens share the room's identity so an
/// external open removes the whole visit. Slug and UUID match after ``RoomNavigationFocusStore``
/// records the alias.
@MainActor
enum ExternalDestinationIdentity {
    static func droppingMatchedVisit(_ path: [HomeRoute], destination: AppDestination) -> [HomeRoute] {
        dropping(path, destination: destination, routeKey: logicalKey(for:))
    }

    static func droppingMatchedVisit(_ path: [FeedRoute], destination: AppDestination) -> [FeedRoute] {
        dropping(path, destination: destination, routeKey: logicalKey(for:))
    }

    static func droppingMatchedVisit(_ path: [MessagesRoute], destination: AppDestination) -> [MessagesRoute] {
        dropping(path, destination: destination, routeKey: logicalKey(for:))
    }

    static func droppingMatchedVisit(_ path: [ProfileRoute], destination: AppDestination) -> [ProfileRoute] {
        dropping(path, destination: destination, routeKey: logicalKey(for:))
    }

    /// Keys whose epoch bump recreates the destination view. Room aliases are included so a
    /// slug route and its UUID route refresh together.
    static func epochKeys(for destination: AppDestination) -> [String] {
        switch destination {
        case .home(.room(let id)), .feed(.room(let id)), .messages(.room(let id)), .profile(.room(let id)):
            return RoomNavigationFocusStore.shared.epochKeys(forRoom: id)
        case .home(let route):
            return [epochKey(for: route)]
        case .feed(let route):
            return [epochKey(for: route)]
        case .messages(let route):
            return [epochKey(for: route)]
        case .profile(let route):
            return [epochKey(for: route)]
        case .auth, .tab, .settingsStack, .sheet, .fullScreen, .compose, .pop, .popToRoot, .dismissPresentation:
            return []
        }
    }

    static func epochKey(for route: HomeRoute) -> String {
        switch route {
        case .room(let id):
            return roomEpochKey(id)
        default:
            return logicalKey(for: route)
        }
    }

    static func epochKey(for route: FeedRoute) -> String {
        switch route {
        case .room(let id):
            return roomEpochKey(id)
        case .roomMembers(let id):
            return "room-members:\(id.rawValue)"
        case .roomInfo(let id):
            return "room-info:\(id.rawValue)"
        case .manageRoom(let id):
            return "room-manage:\(id.rawValue)"
        case .roomSettings(let id):
            return "room-settings:\(id.rawValue)"
        default:
            return logicalKey(for: route)
        }
    }

    static func epochKey(for route: MessagesRoute) -> String {
        switch route {
        case .room(let id):
            return roomEpochKey(id)
        case .roomMembers(let id):
            return "room-members:\(id.rawValue)"
        case .roomInfo(let id):
            return "room-info:\(id.rawValue)"
        case .manageRoom(let id):
            return "room-manage:\(id.rawValue)"
        case .roomSettings(let id):
            return "room-settings:\(id.rawValue)"
        default:
            return logicalKey(for: route)
        }
    }

    static func epochKey(for route: ProfileRoute) -> String {
        switch route {
        case .room(let id):
            return roomEpochKey(id)
        case .roomMembers(let id):
            return "room-members:\(id.rawValue)"
        case .roomInfo(let id):
            return "room-info:\(id.rawValue)"
        case .manageRoom(let id):
            return "room-manage:\(id.rawValue)"
        case .roomSettings(let id):
            return "room-settings:\(id.rawValue)"
        default:
            return logicalKey(for: route)
        }
    }

    static func logicalKey(for destination: AppDestination) -> String? {
        switch destination {
        case .home(let route):
            return logicalKey(for: route)
        case .feed(let route):
            return logicalKey(for: route)
        case .messages(let route):
            return logicalKey(for: route)
        case .profile(let route):
            return logicalKey(for: route)
        case .auth, .tab, .settingsStack, .sheet, .fullScreen, .compose, .pop, .popToRoot, .dismissPresentation:
            return nil
        }
    }

    static func logicalKey(for route: HomeRoute) -> String {
        switch route {
        case .tradeDetail(let id), .socialTrade(let id):
            return "trade:\(id.rawValue)"
        case .post(let id):
            return "post:\(id.rawValue)"
        case .reel(let id):
            return "reel:\(id.rawValue)"
        case .achievementDetail(let id):
            return "achievement:\(id.rawValue)"
        case .otherProfile(let id):
            return "profile:\(id.rawValue)"
        case .room(let id):
            return roomLogicalKey(id)
        case .report(let id):
            return "report:\(id.rawValue)"
        case .tradeRoomJoinRequest(let id):
            return "join-request:\(id)"
        case .activity:
            return "screen:activity"
        case .followRequests:
            return "screen:follow-requests"
        case .rooms:
            return "screen:rooms"
        case .affiliate:
            return "screen:affiliate"
        case .followers(let id):
            return "followers:\(id.rawValue)"
        case .following(let id):
            return "following:\(id.rawValue)"
        case .settings(let settings):
            return "settings:\(settings.rawValue)"
        case .trades:
            return "screen:trades"
        case .calendar:
            return "screen:calendar"
        case .tradingDay(let day):
            return "trading-day:\(day)"
        case .tools:
            return "screen:tools"
        case .propFirm(let id):
            return "prop-firm:\(id.rawValue)"
        case .analyst:
            return "screen:analyst"
        case .backtest:
            return "screen:backtest"
        case .achievements:
            return "screen:achievements"
        case .streaks:
            return "screen:streaks"
        case .reports:
            return "screen:reports"
        case .payouts:
            return "screen:payouts"
        case .withdrawalDetail(let id):
            return "withdrawal:\(id)"
        case .psychologyAnalytics:
            return "screen:psychology-analytics"
        case .tradingScorecard:
            return "screen:trading-scorecard"
        case .psychologyCoach:
            return "screen:psychology-coach"
        case .checkInHistory:
            return "screen:check-in-history"
        case .checkInDay(let day):
            return "check-in-day:\(day)"
        }
    }

    static func logicalKey(for route: FeedRoute) -> String {
        switch route {
        case .post(let id):
            return "post:\(id.rawValue)"
        case .reel(let id):
            return "reel:\(id.rawValue)"
        case .story(let id):
            return "story:\(id.rawValue)"
        case .trade(let id):
            return "trade:\(id.rawValue)"
        case .achievement(let id):
            return "achievement:\(id.rawValue)"
        case .profile(let id):
            return "profile:\(id.rawValue)"
        case .room(let id), .roomMembers(let id), .roomInfo(let id), .manageRoom(let id), .roomSettings(let id):
            return roomLogicalKey(id)
        case .rooms:
            return "screen:rooms"
        case .followers(let id):
            return "followers:\(id.rawValue)"
        case .following(let id):
            return "following:\(id.rawValue)"
        case .explore:
            return "screen:explore"
        case .suggestedTraders:
            return "screen:suggested-traders"
        case .leaderboard:
            return "screen:leaderboard"
        case .settings(let settings):
            return "settings:\(settings.rawValue)"
        }
    }

    static func logicalKey(for route: MessagesRoute) -> String {
        switch route {
        case .thread(let id):
            return "thread:\(id.rawValue)"
        case .sharedTrade(let id):
            return "trade:\(id.rawValue)"
        case .sharedPost(let id):
            return "post:\(id.rawValue)"
        case .sharedReel(let id):
            return "reel:\(id.rawValue)"
        case .sharedAchievement(let id):
            return "achievement:\(id.rawValue)"
        case .profile(let id):
            return "profile:\(id.rawValue)"
        case .room(let id), .roomMembers(let id), .roomInfo(let id), .manageRoom(let id), .roomSettings(let id):
            return roomLogicalKey(id)
        case .rooms:
            return "screen:rooms"
        case .followers(let id):
            return "followers:\(id.rawValue)"
        case .following(let id):
            return "following:\(id.rawValue)"
        case .settings(let settings):
            return "settings:\(settings.rawValue)"
        }
    }

    static func logicalKey(for route: ProfileRoute) -> String {
        switch route {
        case .trade(let id):
            return "trade:\(id.rawValue)"
        case .post(let id):
            return "post:\(id.rawValue)"
        case .reel(let id):
            return "reel:\(id.rawValue)"
        case .achievement(let id):
            return "achievement:\(id.rawValue)"
        case .otherProfile(let id):
            return "profile:\(id.rawValue)"
        case .room(let id), .roomMembers(let id), .roomInfo(let id), .manageRoom(let id), .roomSettings(let id):
            return roomLogicalKey(id)
        case .activity:
            return "screen:activity"
        case .followRequests:
            return "screen:follow-requests"
        case .tradeRoomJoinRequest(let id):
            return "join-request:\(id)"
        case .rooms:
            return "screen:rooms"
        case .affiliate:
            return "screen:affiliate"
        case .followers(let id):
            return "followers:\(id.rawValue)"
        case .following(let id):
            return "following:\(id.rawValue)"
        case .settings(let settings):
            return "settings:\(settings.rawValue)"
        case .referrals:
            return "screen:referrals"
        case .help:
            return "screen:help"
        case .admin(let route):
            return "admin:\(String(describing: route))"
        }
    }

    private static func roomLogicalKey(_ id: RoomID) -> String {
        "room:\(RoomNavigationFocusStore.shared.canonicalRoomID(id).rawValue)"
    }

    private static func roomEpochKey(_ id: RoomID) -> String {
        "room:\(id.rawValue)"
    }

    private static func dropping<Route>(
        _ path: [Route],
        destination: AppDestination,
        routeKey: (Route) -> String
    ) -> [Route] {
        guard let destinationKey = logicalKey(for: destination) else { return path }
        guard let index = path.firstIndex(where: { routeKey($0) == destinationKey }) else { return path }
        return Array(path.prefix(index))
    }
}
