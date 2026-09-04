import Foundation

// MARK: - Per-tab push routes (NavigationStack path elements)

/// Home tab push hierarchy (journal cockpit).
enum HomeRoute: Hashable, Codable, Sendable {
    case trades
    case tradeDetail(TradeID)
    /// Month calendar root.
    case calendar
    /// Futures trading day detail (`YYYY-MM-DD` trading-day key).
    case tradingDay(String)
    case tools
    case propFirm(TradingAccountID)
    case analyst
    case backtest
    case achievements
    case achievementDetail(AchievementID)
    case streaks
    /// AI reports catalog (weekly / monthly / yearly / custom).
    case reports
    /// Owner-only manual payout ledger.
    case payouts
    /// Single report detail (generated or notification deep-link).
    case report(ReportID)
    /// Owner-only psychology analytics detail.
    case psychologyAnalytics
    /// Owner-only psychology coach (AI explains deterministic facts).
    case psychologyCoach
    /// Owner-only check-in history list.
    case checkInHistory
    /// Owner-only check-in + trades for one Eastern trading day.
    case checkInDay(String)
    /// Notifications / Activity inbox opened from Dashboard.
    case activity
    /// Pending follow requests opened from Activity.
    case followRequests
    /// Hierarchical Settings — owned by the Home tab stack that opened Settings.
    case settings(SettingsRoute)
}

/// Feed / Social tab push hierarchy.
enum FeedRoute: Hashable, Codable, Sendable {
    case post(PostID)
    case reel(ReelID)
    case story(StoryID)
    case trade(TradeID)
    case achievement(AchievementID)
    case profile(ProfileID)
    case explore
    case suggestedTraders
    case leaderboard
    case rooms
    case room(RoomID)
    case roomMembers(RoomID)
    case roomInfo(RoomID)
    /// Hierarchical Settings — owned by the Feed tab stack that opened Settings.
    case settings(SettingsRoute)
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
    /// Hierarchical Settings — owned by the Messages tab stack that opened Settings.
    case settings(SettingsRoute)
}

/// Profile (You) tab push hierarchy.
enum ProfileRoute: Hashable, Codable, Sendable {
    case activity
    /// Followers list for a profile (own or other).
    case followers(ProfileID)
    /// Following list for a profile (own or other).
    case following(ProfileID)
    case followRequests
    /// Hierarchical Settings destination — push multiple cases for nested stacks.
    case settings(SettingsRoute)
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

/// Settings navigation hierarchy (Instagram / Apple Settings style).
///
/// Deep-link segments match web `/settings#…` where applicable.
/// Nested leaves (e.g. Messages notification prefs) use hyphenated segments.
enum SettingsRoute: String, Hashable, Codable, Sendable, CaseIterable {
    case home
    case account
    case security
    case profile
    case notifications
    case appearance
    case notificationsMessages = "notifications-messages"
    case notificationsSocial = "notifications-social"
    case notificationsRooms = "notifications-rooms"
    case notificationsAchievements = "notifications-achievements"
    case notificationsProduct = "notifications-product"
    case subscription
    case tradingAccounts = "trading-accounts"
    case privacy
    case privacyBlockedAccounts = "privacy-blocked-accounts"
    case privacyMutedAccounts = "privacy-muted-accounts"
    case privacyMessageAudience = "privacy-message-audience"
    case affiliate
    case support
    case about
    case legalTerms = "legal-terms"
    case legalPrivacy = "legal-privacy"
    case legalCommunityGuidelines = "legal-community-guidelines"
    case legalRefund = "legal-refund"

    var title: String {
        switch self {
        case .home: return "Settings"
        case .account: return "Account"
        case .security: return "Security"
        case .profile: return "Profile"
        case .notifications: return "Notifications"
        case .appearance: return "Appearance"
        case .notificationsMessages: return "Messages"
        case .notificationsSocial: return "Social Activity"
        case .notificationsRooms: return "Trade Rooms"
        case .notificationsAchievements: return "Achievements"
        case .notificationsProduct: return "Product Updates"
        case .subscription: return "Plan"
        case .tradingAccounts: return "Manage Accounts"
        case .privacy: return "Privacy"
        case .privacyBlockedAccounts: return "Blocked Accounts"
        case .privacyMutedAccounts: return "Muted Accounts"
        case .privacyMessageAudience: return "Who Can Message Me"
        case .affiliate: return "Referrals"
        case .support: return "Help & Support"
        case .about: return "About TradeTraxs"
        case .legalTerms: return "Terms & Conditions"
        case .legalPrivacy: return "Privacy Policy"
        case .legalCommunityGuidelines: return "Community Guidelines"
        case .legalRefund: return "Refund Policy"
        }
    }

    /// Parses web hash / path segments, including trading-accounts aliases.
    static func fromDeepLinkSegment(_ raw: String) -> SettingsRoute? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = SettingsRoute(rawValue: key) { return exact }
        switch key {
        case "rules", "dashboard-risk", "copy-trading-groups", "prop-firm":
            return .tradingAccounts
        case "messages":
            return .notificationsMessages
        case "terms", "terms-of-service":
            return .legalTerms
        case "privacy-policy":
            return .legalPrivacy
        case "community-guidelines":
            return .legalCommunityGuidelines
        case "refund", "refund-policy":
            return .legalRefund
        default:
            return nil
        }
    }
}

/// Legacy web settings tab names — retained for call-site clarity.
typealias SettingsSection = SettingsRoute

/// Auth stack routes (pre-main-shell).
enum AuthRoute: Hashable, Codable, Sendable {
    case login
    case resetPassword
    case onboarding
    case choosePlan
    case finishTrial
}
