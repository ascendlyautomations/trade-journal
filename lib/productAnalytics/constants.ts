/** Canonical product analytics event names (must match Supabase allow-list). */
export const PRODUCT_ANALYTICS_EVENTS = {
  sessionStarted: "session_started",
  appOpened: "app_opened",
  screenViewed: "screen_viewed",
  profileViewed: "profile_viewed",
  featureUsed: "feature_used",
  milestoneOnboardingCompleted: "milestone_onboarding_completed",
  milestoneFirstTrade: "milestone_first_trade",
  traxsProPreviewStarted: "traxspro_preview_started",
  traxsProPreviewExited: "traxspro_preview_exited",
  traxsProPreviewUpgradeTapped: "traxspro_preview_upgrade_tapped",
  paywallViewed: "paywall_viewed",
  monetizationUpgradeClicked: "monetization_upgrade_clicked",
} as const

export type ProductAnalyticsEventName =
  (typeof PRODUCT_ANALYTICS_EVENTS)[keyof typeof PRODUCT_ANALYTICS_EVENTS]

/** Standard screen identifiers — stable across web routes and iOS navigation. */
export const PRODUCT_ANALYTICS_SCREENS = {
  dashboard: "dashboard",
  analytics: "analytics",
  calendar: "calendar",
  trades: "trades",
  tradeDetail: "trade_detail",
  feed: "feed",
  messages: "messages",
  messageThread: "message_thread",
  tradeRooms: "trade_rooms",
  tradeRoom: "trade_room",
  explore: "explore",
  profile: "profile",
  profileOther: "profile_other",
  settings: "settings",
  addTrade: "add_trade",
  aiAnalyst: "ai_analyst",
  brokerIntegrations: "broker_integrations",
  onboarding: "onboarding",
  admin: "admin",
  unknown: "unknown",
} as const

export type ProductAnalyticsScreenId =
  (typeof PRODUCT_ANALYTICS_SCREENS)[keyof typeof PRODUCT_ANALYTICS_SCREENS]

/** Feature keys for `feature_used` (one per session by default). */
export const PRODUCT_ANALYTICS_FEATURES = {
  dashboard: "dashboard",
  analytics: "analytics",
  trades: "trades",
  feed: "feed",
  messages: "messages",
  tradeRooms: "trade_rooms",
  aiAnalyst: "ai_analyst",
  brokerIntegrations: "broker_integrations",
  calendar: "calendar",
  explore: "explore",
  addTrade: "add_trade",
  settings: "settings",
} as const

export type ProductAnalyticsFeatureKey =
  (typeof PRODUCT_ANALYTICS_FEATURES)[keyof typeof PRODUCT_ANALYTICS_FEATURES]

export const PRODUCT_ANALYTICS_PLATFORM = "web" as const