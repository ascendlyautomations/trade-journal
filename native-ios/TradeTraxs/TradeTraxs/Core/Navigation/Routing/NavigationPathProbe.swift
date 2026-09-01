#if DEBUG
import SwiftUI

/// DEBUG-only probe exposing live tab paths for UI/integration tests and simulator validation.
///
/// Privacy-safe route summaries — no conversation/profile/trade IDs.
struct NavigationPathProbe: View {
    let store: NavigationStore

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("navigation.probe")
            .accessibilityValue(probeValue)
            .accessibilityAddTraits(.updatesFrequently)
            .allowsHitTesting(false)
    }

    private var probeValue: String {
        let tab = store.selectedTab.rawValue
        let home = NavigationPathProbeFormatter.home(store.paths.home)
        let feed = NavigationPathProbeFormatter.feed(store.paths.feed)
        let messages = NavigationPathProbeFormatter.messages(store.paths.messages)
        let profile = NavigationPathProbeFormatter.profile(store.paths.profile)
        return "tab:\(tab)|home:\(home)|feed:\(feed)|messages:\(messages)|profile:\(profile)"
    }
}

nonisolated enum NavigationPathProbeFormatter {
    static func home(_ path: [HomeRoute]) -> String {
        path.map(homeRoute).joined(separator: ",")
    }

    static func feed(_ path: [FeedRoute]) -> String {
        path.map(feedRoute).joined(separator: ",")
    }

    static func messages(_ path: [MessagesRoute]) -> String {
        path.map(messagesRoute).joined(separator: ",")
    }

    static func profile(_ path: [ProfileRoute]) -> String {
        path.map(profileRoute).joined(separator: ",")
    }

    private static func homeRoute(_ route: HomeRoute) -> String {
        switch route {
        case .trades: return "trades"
        case .tradeDetail: return "tradeDetail"
        case .calendar: return "calendar"
        case .tradingDay: return "tradingDay"
        case .tools: return "tools"
        case .propFirm: return "propFirm"
        case .analyst: return "analyst"
        case .backtest: return "backtest"
        case .achievements: return "achievements"
        case .achievementDetail: return "achievementDetail"
        case .streaks: return "streaks"
        case .reports: return "reports"
        case .payouts: return "payouts"
        case .report: return "report"
        case .settings(let settings): return "settings(\(settings.rawValue))"
        }
    }

    private static func feedRoute(_ route: FeedRoute) -> String {
        switch route {
        case .post: return "post"
        case .reel: return "reel"
        case .story: return "story"
        case .trade: return "trade"
        case .achievement: return "achievement"
        case .profile: return "profile"
        case .explore: return "explore"
        case .suggestedTraders: return "suggestedTraders"
        case .leaderboard: return "leaderboard"
        case .rooms: return "rooms"
        case .room: return "room"
        case .roomMembers: return "roomMembers"
        case .roomInfo: return "roomInfo"
        case .settings(let settings): return "settings(\(settings.rawValue))"
        }
    }

    private static func messagesRoute(_ route: MessagesRoute) -> String {
        switch route {
        case .thread: return "thread"
        case .sharedTrade: return "sharedTrade"
        case .sharedPost: return "sharedPost"
        case .sharedReel: return "sharedReel"
        case .profile: return "profile"
        case .room: return "room"
        case .roomMembers: return "roomMembers"
        case .roomInfo: return "roomInfo"
        case .settings(let settings): return "settings(\(settings.rawValue))"
        }
    }

    private static func profileRoute(_ route: ProfileRoute) -> String {
        switch route {
        case .trade: return "trade"
        case .post: return "post"
        case .reel: return "reel"
        case .achievement: return "achievement"
        case .followers: return "followers"
        case .following: return "following"
        case .otherProfile: return "otherProfile"
        case .rooms: return "rooms"
        case .room: return "room"
        case .roomMembers: return "roomMembers"
        case .roomInfo: return "roomInfo"
        case .settings(let settings): return "settings(\(settings.rawValue))"
        case .help: return "help"
        case .affiliate: return "affiliate"
        case .referrals: return "referrals"
        case .activity: return "activity"
        case .followRequests: return "followRequests"
        }
    }
}
#endif
