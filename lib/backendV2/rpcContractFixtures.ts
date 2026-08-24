/**
 * Sanitized Session/Dashboard bootstrap fixtures for Phase A contract tests.
 * Shapes mirror production RPC output; values are synthetic.
 */

import type { DashboardBootstrapV1, SessionBootstrapV1 } from "./contracts.ts"

const viewerId = "11111111-1111-1111-1111-111111111111"
const accountId = "33333333-3333-3333-3333-333333333333"

function sessionMeta(viewer_id = viewerId) {
  return {
    contract_version: "v1" as const,
    server_time: "2026-08-20T18:00:00.000Z",
    viewer_id,
  }
}

function emptySessionProfile(id: string): SessionBootstrapV1["data"]["session_profile"] {
  return {
    id,
    username: "free_user",
    avatar_url: null,
    is_pro: false,
    creator_access: false,
    subscription_status: null,
    trial_end: null,
    stripe_customer_id: null,
    signup_flow_source: null,
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
    referral_code: null,
    is_beta_tester: false,
    use_free_tier: true,
    onboarding_completed: false,
    has_seen_getting_started_intro: false,
    has_seen_onboarding_complete_popup: false,
    bio: null,
    trading_style: null,
    trader_type: null,
    primary_market: null,
    started_trading: null,
    max_drawdown_limit: null,
    is_private: false,
    has_email_password: false,
  }
}

const proSessionData: SessionBootstrapV1["data"] = {
      viewer: {
        id: viewerId,
        username: "pro_trader",
        display_name: "Pro Trader",
        avatar_url: null,
        is_private: false,
        onboarding_flags: {
          onboarding_completed: true,
          has_seen_getting_started_intro: true,
          has_seen_onboarding_complete_popup: true,
        },
        entitlement: {
          plan: "pro",
          status: "active",
          flags: {
            is_pro: true,
            creator_access: false,
            early_access_active: false,
            use_free_tier: false,
            is_beta_tester: false,
            is_admin: false,
            is_affiliate: false,
          },
        },
      },
      session_profile: {
        ...emptySessionProfile(viewerId),
        username: "pro_trader",
        is_pro: true,
        subscription_status: "active",
        onboarding_completed: true,
      },
      accounts_summary: [
        {
          id: accountId,
          name: "Main",
          type: "live",
          currency: null,
          is_active: true,
        },
      ],
      following_ids: ["22222222-2222-2222-2222-222222222222"],
      badges: { notifications_unread: 2, dm_unread: 3, rooms_unread: null },
      prefs_min: {
        notifications_enabled_summary: true,
        messaging_defaults: {
          likes_enabled: true,
          comments_enabled: true,
          direct_messages_enabled: true,
          followers_enabled: true,
        },
      },
      realtime: {
        channels: ["notifications", "messages", "profiles", "followers"],
      },
    }

export const sessionFixtures = {
  proWithAccounts: {
    meta: sessionMeta(),
    data: proSessionData,
  } satisfies SessionBootstrapV1,

  freeUser: {
    meta: sessionMeta(),
    data: {
      viewer: {
        id: viewerId,
        username: "free_user",
        display_name: null,
        avatar_url: null,
        is_private: false,
        onboarding_flags: {
          onboarding_completed: false,
          has_seen_getting_started_intro: false,
          has_seen_onboarding_complete_popup: false,
        },
        entitlement: {
          plan: "free",
          status: null,
          flags: {
            is_pro: false,
            creator_access: false,
            early_access_active: false,
            use_free_tier: true,
            is_beta_tester: false,
            is_admin: false,
            is_affiliate: false,
          },
        },
      },
      session_profile: emptySessionProfile(viewerId),
      accounts_summary: [],
      following_ids: [],
      badges: { notifications_unread: 0, dm_unread: 0, rooms_unread: null },
      prefs_min: {
        notifications_enabled_summary: true,
        messaging_defaults: {},
      },
      realtime: {
        channels: ["notifications", "messages", "profiles", "followers"],
      },
    },
  } satisfies SessionBootstrapV1,

  trialUser: {
    meta: sessionMeta(),
    data: {
      viewer: {
        id: viewerId,
        username: "trial_user",
        display_name: "Trial",
        avatar_url: null,
        is_private: false,
        onboarding_flags: {
          onboarding_completed: true,
          has_seen_getting_started_intro: true,
          has_seen_onboarding_complete_popup: false,
        },
        entitlement: {
          plan: "pro",
          status: "trialing",
          flags: {
            is_pro: false,
            creator_access: false,
            early_access_active: false,
            use_free_tier: false,
            is_beta_tester: false,
            is_admin: false,
            is_affiliate: false,
          },
        },
      },
      session_profile: {
        ...emptySessionProfile(viewerId),
        username: "trial_user",
        subscription_status: "trialing",
        trial_end: "2026-09-01T00:00:00.000Z",
        onboarding_completed: true,
      },
      accounts_summary: [],
      following_ids: [],
      badges: { notifications_unread: 0, dm_unread: 0, rooms_unread: null },
      prefs_min: {
        notifications_enabled_summary: true,
        messaging_defaults: {},
      },
      realtime: {
        channels: ["notifications", "messages", "profiles", "followers"],
      },
    },
  } satisfies SessionBootstrapV1,

  noAccounts: {
    meta: sessionMeta(),
    data: {
      ...proSessionData,
      accounts_summary: [],
    },
  } satisfies SessionBootstrapV1,

  unreadMessages: {
    meta: sessionMeta(),
    data: {
      ...proSessionData,
      badges: { notifications_unread: 0, dm_unread: 5, rooms_unread: null },
    },
  } satisfies SessionBootstrapV1,
}

const dashboardWithTradesData: DashboardBootstrapV1["data"] = {
      accounts: [
        {
          id: accountId,
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
      trade_window: [
        {
          id: "trade-2",
          pnl: -50,
          mode: "live",
          created_at: "2026-08-02T12:00:00.000Z",
          ticker: "ES",
        },
        {
          id: "trade-1",
          pnl: 100,
          mode: "live",
          created_at: "2026-08-01T12:00:00.000Z",
          ticker: "NQ",
        },
      ],
      trade_window_meta: {
        limit: 500,
        returned: 2,
        history_complete: true,
        total_trade_count: 2,
        oldest_created_at: "2026-08-01T12:00:00.000Z",
        next_cursor: null,
      },
      metrics: {
        total_trades: 2,
        wins: 1,
        losses: 1,
        win_rate: 0.5,
        net_pnl: 50,
        avg_rr: null,
        avg_win: 100,
        avg_loss: -50,
        biggest_win: 100,
        biggest_loss: -50,
      },
      equity_points: [
        { t: "2026-08-01T12:00:00.000Z", v: 100 },
        { t: "2026-08-02T12:00:00.000Z", v: 50 },
      ],
      payout_total: 0,
      recent_trades: [{ id: "trade-2" }, { id: "trade-1" }],
    }

export const dashboardFixtures = {
  withTrades: {
    meta: sessionMeta(),
    data: dashboardWithTradesData,
  } satisfies DashboardBootstrapV1,

  emptyTrades: {
    meta: sessionMeta(),
    data: {
      accounts: [],
      trade_window: [],
      trade_window_meta: {
        limit: 500,
        returned: 0,
        history_complete: true,
        total_trade_count: 0,
        oldest_created_at: null,
        next_cursor: null,
      },
      metrics: {
        total_trades: 0,
        wins: 0,
        losses: 0,
        win_rate: null,
        net_pnl: 0,
        avg_rr: null,
        avg_win: null,
        avg_loss: null,
        biggest_win: null,
        biggest_loss: null,
      },
      equity_points: [],
      payout_total: 0,
      recent_trades: [],
    },
  } satisfies DashboardBootstrapV1,

  noAccounts: {
    meta: sessionMeta(),
    data: {
      ...dashboardWithTradesData,
      accounts: [],
    },
  } satisfies DashboardBootstrapV1,
}
