import Foundation

// MARK: - Per-tab push routes (NavigationStack path elements)

/// Home tab push hierarchy (journal cockpit).
enum HomeRoute: Hashable, Codable, Sendable {
    case trades
    case tradeDetail(TradeID)
    case calendar
    case tools
    case propFirm
    case analyst
    case backtest
    case achievements
    case achievementDetail(AchievementID)
    case streaks
    case report(ReportID)
}

/// Feed / Social tab push hierarchy.
enum FeedRoute: Hashable, Codable, Sendable {
    case post(PostID)
    case reel(ReelID)
    case story(StoryID)
    case trade(TradeID)
    case profile(ProfileID)
    case explore
    case leaderboard
    case rooms
    case room(RoomID)
    case roomMembers(RoomID)
    case roomInfo(RoomID)
}

/// Messages tab push hierarchy (DMs + Trade Rooms opened from inbox).
enum MessagesRoute: Hashable, Codable, Sendable {
    case thread(ConversationID)
    case sharedTrade(TradeID)
    case sharedPost(PostID)
    case sharedReel(ReelID)
    case profile(ProfileID)
    case room(RoomID)
    case roomMembers(RoomID)
    case roomInfo(RoomID)
}

/// Profile (You) tab push hierarchy.
enum ProfileRoute: Hashable, Codable, Sendable {
    case activity
    /// Followers list for a profile (own or other).
    case followers(ProfileID)
    /// Following list for a profile (own or other).
    case following(ProfileID)
    case followRequests
    case settings(SettingsSection?)
    case referrals
    case affiliate
    case help
    case otherProfile(ProfileID)
    case trade(TradeID)
    case post(PostID)
    case reel(ReelID)
    case achievement(AchievementID)
    case rooms
    case room(RoomID)
    case roomMembers(RoomID)
    case roomInfo(RoomID)
}

enum SettingsSection: String, Hashable, Codable, Sendable {
    case account
    case subscription
    case profile
    case tradingAccounts = "trading-accounts"
    case notifications
    case affiliate
}

/// Auth stack routes (pre-main-shell).
enum AuthRoute: Hashable, Codable, Sendable {
    case login
    case resetPassword
    case onboarding
    case choosePlan
    case finishTrial
}
