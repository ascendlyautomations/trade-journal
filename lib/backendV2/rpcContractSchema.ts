/**
 * Phase A: structural contract validators for Session/Dashboard bootstrap RPC payloads.
 * Compares shape, types, and ordering — not server_time (volatile).
 */

import type {
  DashboardBootstrapV1,
  SessionBootstrapV1,
} from "./contracts.ts"

export type RpcContractViolation = {
  path: string
  message: string
  expected?: string
  actual?: string
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function typeOf(value: unknown): string {
  if (value === null) return "null"
  if (Array.isArray(value)) return "array"
  return typeof value
}

function requireKeys(
  obj: Record<string, unknown>,
  keys: string[],
  prefix: string,
  out: RpcContractViolation[]
): void {
  for (const key of keys) {
    if (!(key in obj)) {
      out.push({
        path: `${prefix}.${key}`,
        message: "missing required key",
      })
    }
  }
}

function requireType(
  value: unknown,
  expected: string,
  path: string,
  out: RpcContractViolation[]
): void {
  const actual = typeOf(value)
  if (actual !== expected) {
    out.push({
      path,
      message: "type mismatch",
      expected,
      actual,
    })
  }
}

/** Validates Session bootstrap v1 wire contract (ignores meta.server_time). */
export function validateSessionBootstrapContract(
  raw: SessionBootstrapV1
): RpcContractViolation[] {
  const v: RpcContractViolation[] = []

  if (raw.meta.contract_version !== "v1") {
    v.push({
      path: "meta.contract_version",
      message: "must be v1",
      expected: "v1",
      actual: String(raw.meta.contract_version),
    })
  }

  requireType(raw.meta.viewer_id, "string", "meta.viewer_id", v)

  const data = raw.data
  requireKeys(
    data as unknown as Record<string, unknown>,
    [
      "viewer",
      "session_profile",
      "accounts_summary",
      "following_ids",
      "badges",
      "prefs_min",
      "realtime",
    ],
    "data",
    v
  )

  requireType(data.accounts_summary, "array", "data.accounts_summary", v)
  requireType(data.following_ids, "array", "data.following_ids", v)

  for (const id of data.following_ids) {
    requireType(id, "string", "data.following_ids[]", v)
  }

  for (const acct of data.accounts_summary) {
    requireKeys(
      acct as unknown as Record<string, unknown>,
      ["id", "name", "type", "currency", "is_active"],
      "data.accounts_summary[]",
      v
    )
  }

  const badges = data.badges
  requireType(badges.notifications_unread, "number", "data.badges.notifications_unread", v)
  requireType(badges.dm_unread, "number", "data.badges.dm_unread", v)
  if (badges.rooms_unread !== null) {
    requireType(badges.rooms_unread, "number", "data.badges.rooms_unread", v)
  }

  const viewer = data.viewer
  requireKeys(
    viewer as unknown as Record<string, unknown>,
    [
      "id",
      "username",
      "display_name",
      "avatar_url",
      "is_private",
      "onboarding_flags",
      "entitlement",
    ],
    "data.viewer",
    v
  )
  requireType(viewer.onboarding_flags, "object", "data.viewer.onboarding_flags", v)
  requireType(viewer.entitlement.flags, "object", "data.viewer.entitlement.flags", v)

  const profile = data.session_profile
  const profileKeys = [
    "id",
    "username",
    "avatar_url",
    "is_pro",
    "creator_access",
    "subscription_status",
    "trial_end",
    "stripe_customer_id",
    "signup_flow_source",
    "early_access_enrolled_at",
    "early_access_started_at",
    "early_access_ends_at",
    "early_access_status",
    "early_access_campaign_id",
    "early_access_enrollment_source",
    "lifetime_access_source",
    "lifetime_access_granted_at",
    "is_banned",
    "banned_reason",
    "referral_code",
    "is_beta_tester",
    "use_free_tier",
    "onboarding_completed",
    "has_seen_getting_started_intro",
    "has_seen_onboarding_complete_popup",
    "bio",
    "trading_style",
    "trader_type",
    "primary_market",
    "started_trading",
    "max_drawdown_limit",
    "is_private",
    "has_email_password",
  ] as const
  requireKeys(
    profile as unknown as Record<string, unknown>,
    [...profileKeys],
    "data.session_profile",
    v
  )

  requireType(
    data.prefs_min.messaging_defaults,
    "object",
    "data.prefs_min.messaging_defaults",
    v
  )
  requireType(
    data.prefs_min.notifications_enabled_summary,
    "boolean",
    "data.prefs_min.notifications_enabled_summary",
    v
  )
  requireType(data.realtime.channels, "array", "data.realtime.channels", v)

  return v
}

/** Validates Dashboard bootstrap v1 wire contract. */
export function validateDashboardBootstrapContract(
  raw: DashboardBootstrapV1
): RpcContractViolation[] {
  const v: RpcContractViolation[] = []

  if (raw.meta.contract_version !== "v1") {
    v.push({
      path: "meta.contract_version",
      message: "must be v1",
      expected: "v1",
      actual: String(raw.meta.contract_version),
    })
  }

  const data = raw.data
  requireKeys(
    data as unknown as Record<string, unknown>,
    [
      "accounts",
      "trade_window",
      "trade_window_meta",
      "metrics",
      "equity_points",
      "payout_total",
      "recent_trades",
    ],
    "data",
    v
  )

  requireType(data.accounts, "array", "data.accounts", v)
  requireType(data.trade_window, "array", "data.trade_window", v)
  requireType(data.recent_trades, "array", "data.recent_trades", v)
  requireType(data.equity_points, "array", "data.equity_points", v)

  const meta = data.trade_window_meta
  requireKeys(
    meta as unknown as Record<string, unknown>,
    [
      "limit",
      "returned",
      "history_complete",
      "total_trade_count",
      "oldest_created_at",
      "next_cursor",
    ],
    "data.trade_window_meta",
    v
  )
  requireType(meta.limit, "number", "data.trade_window_meta.limit", v)
  requireType(meta.returned, "number", "data.trade_window_meta.returned", v)
  requireType(meta.history_complete, "boolean", "data.trade_window_meta.history_complete", v)
  requireType(meta.total_trade_count, "number", "data.trade_window_meta.total_trade_count", v)
  requireType(meta.next_cursor, "null", "data.trade_window_meta.next_cursor", v)

  if (data.payout_total !== null) {
    requireType(data.payout_total, "number", "data.payout_total", v)
  }

  requireType(data.metrics, "object", "data.metrics", v)

  for (const pt of data.equity_points) {
    if (!isObject(pt)) continue
    requireType(pt.t, "string", "data.equity_points[].t", v)
    requireType(pt.v, "number", "data.equity_points[].v", v)
  }

  return v
}

/** Deep semantic compare for regression tests (excludes volatile meta.server_time). */
export function compareSessionBootstrapSemantics(
  a: SessionBootstrapV1,
  b: SessionBootstrapV1
): RpcContractViolation[] {
  const v: RpcContractViolation[] = []

  const strip = (s: SessionBootstrapV1) => {
    const copy = JSON.parse(JSON.stringify(s)) as SessionBootstrapV1
    copy.meta.server_time = "FIXED"
    return copy
  }

  const sa = strip(a)
  const sb = strip(b)
  if (JSON.stringify(sa) !== JSON.stringify(sb)) {
    v.push({
      path: "session",
      message: "semantic payload mismatch (excluding server_time)",
    })
  }
  return v
}

export function compareDashboardBootstrapSemantics(
  a: DashboardBootstrapV1,
  b: DashboardBootstrapV1
): RpcContractViolation[] {
  const v: RpcContractViolation[] = []

  const strip = (d: DashboardBootstrapV1) => {
    const copy = JSON.parse(JSON.stringify(d)) as DashboardBootstrapV1
    copy.meta.server_time = "FIXED"
    return copy
  }

  if (JSON.stringify(strip(a)) !== JSON.stringify(strip(b))) {
    v.push({
      path: "dashboard",
      message: "semantic payload mismatch (excluding server_time)",
    })
  }
  return v
}

/** Account summary arrays must stay ordered by created_at asc, id asc (by id order proxy). */
export function assertAccountOrderingStable(
  accounts: Array<{ id: string }>,
  path: string
): RpcContractViolation[] {
  const ids = accounts.map((a) => String(a.id))
  const sorted = [...ids].sort()
  if (JSON.stringify(ids) === JSON.stringify(sorted)) {
    return []
  }
  return [
    {
      path,
      message: "accounts must be ordered by created_at asc, id asc (ids not lex-sorted — order preserved)",
    },
  ]
}
