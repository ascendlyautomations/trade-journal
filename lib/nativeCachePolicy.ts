/**
 * Soft TTL policy for native silent caching (stale-while-revalidate).
 * Soft-expired entries are still painted; pages always refresh in background.
 */

export const NATIVE_CACHE_NS = {
  dashboardTrades: "dashboard_trades",
  dashboardAccounts: "dashboard_accounts",
  feed: "feed",
  explore: "explore",
  messagesInbox: "messages_inbox",
  conversation: "conversation",
  rooms: "rooms",
  profile: "profile",
  tradeDetail: "trade_detail",
  notifications: "notifications",
  leaderboard: "leaderboard",
} as const

export type NativeCacheNamespace =
  (typeof NATIVE_CACHE_NS)[keyof typeof NATIVE_CACHE_NS]

/** Soft freshness windows (ms). 0 = always treat as needing refresh. */
export const NATIVE_CACHE_SOFT_TTL_MS: Record<NativeCacheNamespace, number> = {
  dashboard_trades: 45_000,
  dashboard_accounts: 45_000,
  feed: 60_000,
  explore: 60_000,
  messages_inbox: 0,
  conversation: 0,
  rooms: 0,
  profile: 5 * 60_000,
  trade_detail: 5 * 60_000,
  notifications: 0,
  leaderboard: 5 * 60_000,
}

/** Max conversation threads persisted to IndexedDB per user. */
export const NATIVE_CONVERSATION_PERSIST_MAX = 10

/** Cap messages persisted per conversation / room channel. */
export const NATIVE_MESSAGES_PERSIST_MAX = 80
