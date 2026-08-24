/**
 * Shared Backend V2 bootstrap contract models (v1).
 * Wire format: snake_case JSON. Apps must not depend on DB schema.
 * Phase 1: types + decode helpers only — not wired to screens.
 */

import {
  assertContractVersion,
  type BootstrapMetaV1,
  type BackendV2ContractVersion,
} from "./versioning.ts"

export type { BootstrapMetaV1, BackendV2ContractVersion }

export type BackendV2Cursor = string | null

export type ViewerCardV1 = {
  id: string
  username: string | null
  display_name: string | null
  avatar_url: string | null
  is_private: boolean
  onboarding_flags: Record<string, boolean>
  entitlement: {
    plan: string
    status: string | null
    flags: Record<string, boolean>
  }
}

export type AccountSummaryV1 = {
  id: string
  name: string | null
  type: string | null
  currency: string | null
  is_active: boolean
}

export type BadgeCountsV1 = {
  notifications_unread: number
  dm_unread: number
  rooms_unread: number | null
}

export type EngagementSnapshotV1 = {
  like_count: number
  comment_count: number
  liked_by_viewer: boolean
}

export type AuthorCardV1 = {
  id: string
  username: string | null
  display_name: string | null
  avatar_url: string | null
  is_verified?: boolean
}

export type FollowEdgeV1 = {
  is_following: boolean
  is_followed_by: boolean
  request_pending: boolean
  follower_count: number
  following_count: number
}

// —— Session ——

export type SessionProfileV1 = {
  id: string
  username: string | null
  avatar_url: string | null
  is_pro: boolean | null
  creator_access: boolean | null
  subscription_status: string | null
  trial_end: string | null
  stripe_customer_id: string | null
  signup_flow_source: string | null
  early_access_enrolled_at: string | null
  early_access_started_at: string | null
  early_access_ends_at: string | null
  early_access_status: string | null
  early_access_campaign_id: string | null
  early_access_enrollment_source: string | null
  lifetime_access_source: string | null
  lifetime_access_granted_at: string | null
  is_banned: boolean | null
  banned_reason: string | null
  referral_code: string | null
  is_beta_tester: boolean | null
  use_free_tier: boolean | null
  onboarding_completed: boolean | null
  has_seen_getting_started_intro: boolean | null
  has_seen_onboarding_complete_popup: boolean | null
  bio: string | null
  trading_style: string | null
  trader_type: string | null
  primary_market: string | null
  started_trading: string | null
  max_drawdown_limit: number | null
  is_private: boolean | null
  has_email_password: boolean | null
}

export type SessionBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    viewer: ViewerCardV1
    /** Gate/shell profile slice — maps to existing UserProfileSlice fields. */
    session_profile: SessionProfileV1
    accounts_summary: AccountSummaryV1[]
    following_ids: string[]
    badges: BadgeCountsV1
    prefs_min: {
      notifications_enabled_summary: boolean
      messaging_defaults: Record<string, unknown>
    }
    realtime: {
      channels: string[]
    }
  }
}

// —— Dashboard ——

export type DashboardAccountV1 = {
  id: string
  account_number?: string | number | null
  name: string | null
  account_size?: number | null
  mode?: string | null
  category?: string | null
  is_active?: boolean | null
  can_add_trades?: boolean | null
  note?: string | null
  consistency?: number | null
  max_drawdown?: number | null
  daily_drawdown?: number | null
  profit_target?: number | null
  winning_days?: number | null
  winning_day_threshold?: number | null
  /** Session-summary compat aliases */
  type?: string | null
  currency?: string | null
}

export type DashboardTradeWindowMetaV1 = {
  limit: number
  returned: number
  history_complete: boolean
  total_trade_count: number
  oldest_created_at: string | null
  next_cursor: string | null
}

export type DashboardBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    /** Full trading accounts (ACCOUNTS_SELECT-shaped). Not session accounts_summary. */
    accounts: DashboardAccountV1[]
    trade_window: Record<string, unknown>[]
    trade_window_meta: DashboardTradeWindowMetaV1
    metrics: Record<string, number | null>
    equity_points: Array<{ t: string; v: number }>
    payout_total: number | null
    recent_trades: Record<string, unknown>[]
  }
}

// —— Feed ——

export type FeedItemKindV1 =
  | "post"
  | "profile_post"
  | "reel"
  | "achievement_post"
  | "trade_card"

export type FeedContentFilterV1 =
  | "all"
  | "trades"
  | "reels"
  | "posts"
  | "achievements"

export type FeedItemV1 = {
  kind: FeedItemKindV1
  id: string
  created_at: string
  author_id: string
  /** Card-shaped row (snake_case). Web maps into FeedItem. */
  payload: Record<string, unknown>
}

export type FeedStoryPreviewV1 = {
  id: string
  user_id: string
  image_url: string
  created_at: string
}

export type FeedPageMetaV1 = {
  limit: number
  returned: number
  has_more: boolean
}

export type FeedBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    scope: "following" | "global"
    content_filter: FeedContentFilterV1
    items: FeedItemV1[]
    authors: Record<string, AuthorCardV1>
    engagement: Record<string, EngagementSnapshotV1>
    /** Following-scope only; empty for global. Feed-owned. */
    stories: FeedStoryPreviewV1[]
    story_authors: Record<string, AuthorCardV1>
    next_cursor: BackendV2Cursor
    page_meta: FeedPageMetaV1
    /** Echo of Session SocialGraph — not Session ownership transfer. */
    following_ids_echo: string[]
  }
}

// —— Profile ——

export type ProfileBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    profile: AuthorCardV1 & {
      bio: string | null
      is_private: boolean
      trader_type: string | null
    }
    stats: Record<string, number | null>
    follow_edge: FollowEdgeV1
    owned_room: { id: string; name: string | null } | null
    tab_availability: {
      trades: boolean
      posts: boolean
      reels: boolean
      achievements: boolean
    }
  }
}

export type ProfileTabBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    tab: "trades" | "posts" | "reels" | "achievements"
    items: Record<string, unknown>[]
    engagement: Record<string, EngagementSnapshotV1>
    next_cursor: BackendV2Cursor
  }
}

// —— Messaging / Rooms ——

export type MessagingParticipantV1 = {
  user_id: string
  username: string | null
  display_name: string | null
  avatar_url: string | null
}

export type MessagingConversationV1 = {
  id: string
  is_group: boolean
  is_pinned: boolean
  name: string | null
  avatar_url: string | null
  last_message: string | null
  last_message_at: string | null
  unread_count: number
  muted: boolean
  participants: MessagingParticipantV1[]
}

/** Messaging inbox bootstrap — DM/group conversations only (Rooms are separate). */
export type MessagesBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    conversations: MessagingConversationV1[]
    peers: Record<string, AuthorCardV1>
    /** Messaging computes; Session stores for Navbar badges. */
    dm_unread_total: number
    muted_ids: string[]
    /** Phase C: count of message-type notifications marked read on inbox open (optional). */
    message_notifications_marked_read?: number
    next_cursor: BackendV2Cursor
    page_meta: {
      limit: number
      returned: number
      has_more: boolean
    }
  }
}

export type ConversationBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    conversation: Record<string, unknown>
    peer: AuthorCardV1 | null
    messages: Record<string, unknown>[]
    prefs: Record<string, unknown>
    block_status: { blocked: boolean; blocked_by: boolean }
    next_cursor: BackendV2Cursor
  }
}

export type RoomsBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    room: Record<string, unknown>
    membership: Record<string, unknown> | null
    messages: Record<string, unknown>[]
    sections: Record<string, unknown>[] | null
    unread: number
    peers: Record<string, AuthorCardV1>
    next_cursor: BackendV2Cursor
  }
}

// —— Activity / Explore / Leaderboard ——

export type ActivityBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    notifications: Record<string, unknown>[]
    actors: Record<string, AuthorCardV1>
    follow_requests: Record<string, unknown>[]
    unread_total: number
    next_cursor: BackendV2Cursor
  }
}

export type ExploreBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    traders: Record<string, unknown>[]
    rooms: Record<string, unknown>[]
    social_counts: Record<string, { followers: number; following: number }>
    following_ids: string[]
    activity_meta: Record<string, unknown>
  }
}

export type LeaderboardBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    timeframe: string
    category: string
    rows: Record<string, unknown>[]
    next_cursor: BackendV2Cursor
  }
}

// —— Calendar / Trades / Detail / Settings ——

export type CalendarBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    year: number
    month: number
    accounts: AccountSummaryV1[]
    day_buckets: Record<string, unknown>[]
    trades_by_day: Record<string, Record<string, unknown>[]>
    metrics_month: Record<string, number | null>
  }
}

export type TradeDetailBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    trade: Record<string, unknown>
    author: AuthorCardV1
    engagement: EngagementSnapshotV1
    comments_page: Record<string, unknown>[] | null
    viewer_state: Record<string, unknown>
    next_comments_cursor: BackendV2Cursor
  }
}

export type SettingsBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    profile_settings: Record<string, unknown>
    notification_prefs: Record<string, unknown>
    messaging_prefs: Record<string, unknown>
    accounts: AccountSummaryV1[]
    entitlement: ViewerCardV1["entitlement"]
  }
}

export type BackendV2BootstrapContract =
  | SessionBootstrapV1
  | DashboardBootstrapV1
  | FeedBootstrapV1
  | ProfileBootstrapV1
  | ProfileTabBootstrapV1
  | MessagesBootstrapV1
  | ConversationBootstrapV1
  | RoomsBootstrapV1
  | ActivityBootstrapV1
  | ExploreBootstrapV1
  | LeaderboardBootstrapV1
  | CalendarBootstrapV1
  | TradeDetailBootstrapV1
  | SettingsBootstrapV1

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

export function parseBootstrapEnvelope<T extends { meta: BootstrapMetaV1 }>(
  raw: unknown,
  label: string
): T {
  if (!isObject(raw)) {
    throw new Error(`${label}: expected object`)
  }
  if (!isObject(raw.meta) || !isObject(raw.data)) {
    throw new Error(`${label}: expected { meta, data }`)
  }
  assertContractVersion(raw.meta as BootstrapMetaV1)
  return raw as T
}

export function decodeSessionBootstrapV1(raw: unknown): SessionBootstrapV1 {
  const envelope = parseBootstrapEnvelope<SessionBootstrapV1>(
    raw,
    "SessionBootstrapV1"
  )
  if (!isObject(envelope.data.viewer)) {
    throw new Error("SessionBootstrapV1: missing viewer")
  }
  if (!isObject(envelope.data.session_profile)) {
    throw new Error("SessionBootstrapV1: missing session_profile")
  }
  if (!Array.isArray(envelope.data.following_ids)) {
    throw new Error("SessionBootstrapV1: following_ids must be an array")
  }
  if (!isObject(envelope.data.badges)) {
    throw new Error("SessionBootstrapV1: missing badges")
  }
  return envelope
}

export function decodeDashboardBootstrapV1(raw: unknown): DashboardBootstrapV1 {
  const envelope = parseBootstrapEnvelope<DashboardBootstrapV1>(
    raw,
    "DashboardBootstrapV1"
  )
  if (!Array.isArray(envelope.data.accounts)) {
    throw new Error("DashboardBootstrapV1: accounts must be an array")
  }
  if (!Array.isArray(envelope.data.trade_window)) {
    throw new Error("DashboardBootstrapV1: trade_window must be an array")
  }
  if (!isObject(envelope.data.trade_window_meta)) {
    throw new Error("DashboardBootstrapV1: missing trade_window_meta")
  }
  return envelope
}

export function decodeFeedBootstrapV1(raw: unknown): FeedBootstrapV1 {
  const envelope = parseBootstrapEnvelope<FeedBootstrapV1>(raw, "FeedBootstrapV1")
  if (!Array.isArray(envelope.data.items)) {
    throw new Error("FeedBootstrapV1: items must be an array")
  }
  if (!Array.isArray(envelope.data.stories)) {
    envelope.data.stories = []
  }
  if (!isObject(envelope.data.story_authors)) {
    envelope.data.story_authors = {}
  }
  if (!isObject(envelope.data.page_meta)) {
    envelope.data.page_meta = {
      limit: envelope.data.items.length,
      returned: envelope.data.items.length,
      has_more: Boolean(envelope.data.next_cursor),
    }
  }
  if (envelope.data.content_filter == null) {
    envelope.data.content_filter = "all"
  }
  return envelope
}

export function decodeProfileBootstrapV1(raw: unknown): ProfileBootstrapV1 {
  return parseBootstrapEnvelope(raw, "ProfileBootstrapV1")
}

export function decodeMessagesBootstrapV1(raw: unknown): MessagesBootstrapV1 {
  const envelope = parseBootstrapEnvelope<MessagesBootstrapV1>(
    raw,
    "MessagesBootstrapV1"
  )
  if (!Array.isArray(envelope.data.conversations)) {
    throw new Error("MessagesBootstrapV1: conversations must be an array")
  }
  if (typeof envelope.data.dm_unread_total !== "number") {
    throw new Error("MessagesBootstrapV1: dm_unread_total must be a number")
  }
  return envelope
}

export function decodeRoomsBootstrapV1(raw: unknown): RoomsBootstrapV1 {
  return parseBootstrapEnvelope(raw, "RoomsBootstrapV1")
}

export function decodeActivityBootstrapV1(raw: unknown): ActivityBootstrapV1 {
  return parseBootstrapEnvelope(raw, "ActivityBootstrapV1")
}

export function decodeExploreBootstrapV1(raw: unknown): ExploreBootstrapV1 {
  return parseBootstrapEnvelope(raw, "ExploreBootstrapV1")
}

export function decodeLeaderboardBootstrapV1(
  raw: unknown
): LeaderboardBootstrapV1 {
  return parseBootstrapEnvelope(raw, "LeaderboardBootstrapV1")
}

export function decodeCalendarBootstrapV1(raw: unknown): CalendarBootstrapV1 {
  return parseBootstrapEnvelope(raw, "CalendarBootstrapV1")
}

export function decodeTradeDetailBootstrapV1(
  raw: unknown
): TradeDetailBootstrapV1 {
  return parseBootstrapEnvelope(raw, "TradeDetailBootstrapV1")
}

export function decodeSettingsBootstrapV1(raw: unknown): SettingsBootstrapV1 {
  return parseBootstrapEnvelope(raw, "SettingsBootstrapV1")
}
