import Foundation

/// Maps native navigation destinations → product analytics screen ids (stack + tabs).
enum ProductAnalyticsScreenTracking {
    static func trackHome(_ route: HomeRoute) {
        switch route {
        case .trades:
            ProductAnalyticsCoordinator.shared.noteScreen(.trades)
        case .tradeDetail:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeDetail)
        case .calendar, .tradingDay:
            ProductAnalyticsCoordinator.shared.noteScreen(.calendar)
        case .reports, .report:
            ProductAnalyticsCoordinator.shared.noteScreen(.reports)
        case .psychologyAnalytics, .psychologyCoach:
            ProductAnalyticsCoordinator.shared.noteScreen(.analytics)
        case .analyst:
            ProductAnalyticsCoordinator.shared.noteScreen(.aiAnalyst)
        case .rooms:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRooms)
        case .room:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRoom)
        case .settings:
            ProductAnalyticsCoordinator.shared.noteScreen(.settings)
        default:
            break
        }
    }

    static func trackFeed(_ route: FeedRoute) {
        switch route {
        case .explore, .suggestedTraders:
            ProductAnalyticsCoordinator.shared.noteScreen(.explore)
        case .rooms:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRooms)
        case .room:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRoom)
        case .settings:
            ProductAnalyticsCoordinator.shared.noteScreen(.settings)
        default:
            break
        }
    }

    static func trackMessages(_ route: MessagesRoute) {
        switch route {
        case .thread:
            ProductAnalyticsCoordinator.shared.noteScreen(.messageThread)
        case .rooms:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRooms)
        case .room:
            ProductAnalyticsCoordinator.shared.noteScreen(.tradeRoom)
        case .settings:
            ProductAnalyticsCoordinator.shared.noteScreen(.settings)
        default:
            break
        }
    }

    static func trackProfile(_ route: ProfileRoute) {
        switch route {
        case .settings:
            ProductAnalyticsCoordinator.shared.noteScreen(.settings)
        default:
            break
        }
    }
}