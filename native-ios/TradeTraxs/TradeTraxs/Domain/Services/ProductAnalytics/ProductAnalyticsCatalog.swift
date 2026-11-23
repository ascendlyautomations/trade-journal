import Foundation

/// Canonical names — must match Supabase `product_analytics_allowed_event_names()`.
nonisolated enum ProductAnalyticsEventName: String, Sendable {
    case sessionStarted = "session_started"
    case appOpened = "app_opened"
    case screenViewed = "screen_viewed"
    case profileViewed = "profile_viewed"
    case featureUsed = "feature_used"
    case milestoneOnboardingCompleted = "milestone_onboarding_completed"
    case milestoneFirstTrade = "milestone_first_trade"
    case traxsProPreviewStarted = "traxspro_preview_started"
    case traxsProPreviewExited = "traxspro_preview_exited"
    case traxsProPreviewUpgradeTapped = "traxspro_preview_upgrade_tapped"
    case paywallViewed = "paywall_viewed"
    case monetizationUpgradeClicked = "monetization_upgrade_clicked"
}

nonisolated enum ProductAnalyticsScreenID: String, Sendable {
    case dashboard
    case analytics
    case calendar
    case trades
    case tradeDetail
    case feed
    case messages
    case messageThread
    case tradeRooms
    case tradeRoom
    case explore
    case profile
    case profileOther
    case settings
    case addTrade
    case aiAnalyst
    case brokerIntegrations
    case onboarding
    case admin
    case reports
    case unknown
}

/// Raw values match web `featureKeyFromScreen` (snake_case).
nonisolated enum ProductAnalyticsFeatureKey: String, Sendable {
    case dashboard
    case analytics
    case trades
    case feed
    case messages
    case tradeRooms = "trade_rooms"
    case aiAnalyst = "ai_analyst"
    case brokerIntegrations = "broker_integrations"
    case calendar
    case explore
    case addTrade = "add_trade"
    case settings
    case profile
    case reports
}

nonisolated enum ProductAnalyticsPlatform: String, Sendable {
    case ios
    case web
}