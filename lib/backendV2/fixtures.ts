/**
 * Golden JSON fixtures for Backend V2 contract decode tests.
 * Keep in sync with native-ios BackendV2ContractFixtures.swift
 */

import type {
  ActivityBootstrapV1,
  CalendarBootstrapV1,
  DashboardBootstrapV1,
  ExploreBootstrapV1,
  FeedBootstrapV1,
  LeaderboardBootstrapV1,
  MessagesBootstrapV1,
  ProfileBootstrapV1,
  RoomsBootstrapV1,
  SessionBootstrapV1,
  SettingsBootstrapV1,
  TradeDetailBootstrapV1,
} from "./contracts.ts"

const meta = {
  contract_version: "v1" as const,
  server_time: "2026-08-19T20:00:00.000Z",
  viewer_id: "11111111-1111-1111-1111-111111111111",
}

const author = {
  id: "22222222-2222-2222-2222-222222222222",
  username: "trader_a",
  display_name: "Trader A",
  avatar_url: null as string | null,
}

export const sessionBootstrapFixture: SessionBootstrapV1 = {
  meta,
  data: {
    viewer: {
      id: meta.viewer_id!,
      username: "viewer",
      display_name: "Viewer",
      avatar_url: null,
      is_private: false,
      onboarding_flags: { completed: true },
      entitlement: {
        plan: "pro",
        status: "active",
        flags: { early_access: false },
      },
    },
    accounts_summary: [
      {
        id: "33333333-3333-3333-3333-333333333333",
        name: "Main",
        type: "live",
        currency: "USD",
        is_active: true,
      },
    ],
    following_ids: [author.id],
    badges: {
      notifications_unread: 2,
      dm_unread: 1,
      rooms_unread: 0,
    },
    prefs_min: {
      notifications_enabled_summary: true,
      messaging_defaults: {},
    },
    realtime: {
      channels: ["notifications", "messages"],
    },
    session_profile: {
      id: meta.viewer_id!,
      username: "viewer",
      avatar_url: null,
      is_pro: true,
      creator_access: false,
      subscription_status: "active",
      trial_end: null,
      stripe_customer_id: null,
      signup_flow_source: "standard_email",
      early_access_enrolled_at: null,
      early_access_started_at: null,
      early_access_ends_at: null,
      early_access_status: null,
      early_access_campaign_id: null,
      early_access_enrollment_source: null,
      lifetime_access_source: null,
      lifetime_access_granted_at: null,
      is_banned: false,
      banned_reason: null,
      referral_code: "VIEWER1",
      is_beta_tester: false,
      use_free_tier: false,
      onboarding_completed: true,
      has_seen_getting_started_intro: true,
      has_seen_onboarding_complete_popup: true,
      bio: null,
      trading_style: null,
      trader_type: "day",
      primary_market: null,
      started_trading: null,
      max_drawdown_limit: null,
      is_private: false,
      has_email_password: true,
    },
  },
}

export const dashboardBootstrapFixture: DashboardBootstrapV1 = {
  meta,
  data: {
    accounts: [
      {
        id: "33333333-3333-3333-3333-333333333333",
        account_number: 1,
        name: "Main",
        account_size: 50000,
        mode: "live",
        category: "personal",
        is_active: true,
        can_add_trades: true,
        note: null,
        consistency: null,
        max_drawdown: null,
        daily_drawdown: null,
        profit_target: null,
        winning_days: null,
        winning_day_threshold: null,
      },
    ],
    trade_window: [{ id: "t1", pnl: 100, mode: "live" }],
    trade_window_meta: {
      limit: 500,
      returned: 1,
      history_complete: true,
      total_trade_count: 1,
      oldest_created_at: "2026-08-01T00:00:00.000Z",
      next_cursor: null,
    },
    metrics: { win_rate: 0.55, net_pnl: 100, total_trades: 1 },
    equity_points: [{ t: "2026-08-01", v: 1000 }],
    payout_total: 0,
    recent_trades: [{ id: "t1" }],
  },
}

export const feedBootstrapFixture: FeedBootstrapV1 = {
  meta,
  data: {
    scope: "following",
    content_filter: "all",
    items: [
      {
        kind: "post",
        id: "p1",
        created_at: meta.server_time,
        author_id: author.id,
        payload: { caption: "hello" },
      },
    ],
    authors: { [author.id]: author },
    engagement: {
      p1: { like_count: 3, comment_count: 1, liked_by_viewer: false },
    },
    stories: [],
    story_authors: {},
    next_cursor: null,
    page_meta: { limit: 8, returned: 1, has_more: false },
    following_ids_echo: [author.id],
  },
}

export const profileBootstrapFixture: ProfileBootstrapV1 = {
  meta,
  data: {
    profile: {
      ...author,
      bio: "bio",
      is_private: false,
      trader_type: "day",
    },
    stats: { trades: 10, followers: 5 },
    follow_edge: {
      is_following: true,
      is_followed_by: false,
      request_pending: false,
      follower_count: 5,
      following_count: 2,
    },
    owned_room: null,
    tab_availability: {
      trades: true,
      posts: true,
      reels: true,
      achievements: true,
    },
  },
}

export const messagesBootstrapFixture: MessagesBootstrapV1 = {
  meta,
  data: {
    conversations: [
      {
        id: "c1111111-1111-1111-1111-111111111111",
        is_group: false,
        is_pinned: false,
        name: null,
        avatar_url: null,
        last_message: "hey",
        last_message_at: "2026-08-19T19:00:00.000Z",
        unread_count: 1,
        muted: false,
        participants: [
          {
            user_id: meta.viewer_id!,
            username: "viewer",
            display_name: "Viewer",
            avatar_url: null,
          },
          {
            user_id: author.id,
            username: author.username,
            display_name: author.display_name,
            avatar_url: null,
          },
        ],
      },
    ],
    peers: { [author.id]: author },
    dm_unread_total: 1,
    muted_ids: [],
    next_cursor: null,
    page_meta: { limit: 40, returned: 1, has_more: false },
  },
}

export const roomsBootstrapFixture: RoomsBootstrapV1 = {
  meta,
  data: {
    room: { id: "r1", name: "Room" },
    membership: { role: "member" },
    messages: [{ id: "m1" }],
    sections: null,
    unread: 0,
    peers: { [author.id]: author },
    next_cursor: null,
  },
}

export const activityBootstrapFixture: ActivityBootstrapV1 = {
  meta,
  data: {
    notifications: [{ id: "n1", type: "like" }],
    actors: { [author.id]: author },
    follow_requests: [],
    unread_total: 2,
    next_cursor: null,
  },
}

export const exploreBootstrapFixture: ExploreBootstrapV1 = {
  meta,
  data: {
    traders: [{ id: author.id }],
    rooms: [],
    social_counts: { [author.id]: { followers: 5, following: 2 } },
    following_ids: [author.id],
    activity_meta: {},
  },
}

export const leaderboardBootstrapFixture: LeaderboardBootstrapV1 = {
  meta,
  data: {
    timeframe: "7d",
    category: "pnl",
    rows: [{ profile_id: author.id, pnl: 100 }],
    next_cursor: null,
  },
}

export const calendarBootstrapFixture: CalendarBootstrapV1 = {
  meta,
  data: {
    year: 2026,
    month: 8,
    accounts: sessionBootstrapFixture.data.accounts_summary,
    day_buckets: [{ day: "2026-08-01", pnl: 10 }],
    trades_by_day: { "2026-08-01": [{ id: "t1" }] },
    metrics_month: { net_pnl: 10 },
  },
}

export const tradeDetailBootstrapFixture: TradeDetailBootstrapV1 = {
  meta,
  data: {
    trade: { id: "t1", ticker: "ES" },
    author,
    engagement: { like_count: 1, comment_count: 0, liked_by_viewer: true },
    comments_page: [],
    viewer_state: { can_edit: true },
    next_comments_cursor: null,
  },
}

export const settingsBootstrapFixture: SettingsBootstrapV1 = {
  meta,
  data: {
    profile_settings: { username: "viewer" },
    notification_prefs: { likes: true },
    messaging_prefs: {},
    accounts: sessionBootstrapFixture.data.accounts_summary,
    entitlement: sessionBootstrapFixture.data.viewer.entitlement,
  },
}
