/**
 * "Nothing Else Comes Close" comparison table — audited feature rows.
 *
 * TradeTraxs (tt): platform capability (Pro unlocks premium analytics, AI, etc.).
 * Competitors: conservative ratings from public product pages (2026); use partial
 * when capability exists but is narrower than TradeTraxs or tier-limited.
 *
 * Wording aligns with {@link TRADETRAXS_PRO_PLAN} / pricing page where applicable.
 */

import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "./tradeTraxsPlans.ts"

export type ComparisonTriState = "full" | "partial" | "none"

export type LandingComparisonRow = {
  feature: string
  tt: ComparisonTriState
  tz: ComparisonTriState
  ts: ComparisonTriState
  excel: ComparisonTriState
  discord: ComparisonTriState
}

/** Row labels — strongest differentiators first; names match pricing copy. */
export const LANDING_COMPARISON_FEATURE_LABELS = {
  performanceAnalytics: TRADETRAXS_PRO_PLAN.features[1],
  aiTradeAnalyst: TRADETRAXS_PRO_PLAN.features[2],
  backtestLab: TRADETRAXS_PRO_PLAN.features[3],
  propFirmMode: TRADETRAXS_PRO_PLAN.features[4],
  tradingCommunity: "Trading Community",
  tradeRooms: TRADETRAXS_FREE_PLAN.features[2],
  tradingReels: "Trading Reels",
  directMessaging: "Direct Messaging",
  tradeReplayVideos: TRADETRAXS_PRO_PLAN.features[5],
  unlimitedTradeJournaling: TRADETRAXS_PRO_PLAN.features[0],
  multipleTradingAccounts: "Track Multiple Trading Accounts",
  screenshotUploads: "Screenshot Uploads",
  mobileFriendly: "Mobile-Friendly Experience",
  continuousUpdates: "Continuous Feature Updates",
} as const

export const LANDING_COMPARISON_ROWS: readonly LandingComparisonRow[] = [
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.performanceAnalytics,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "partial",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.aiTradeAnalyst,
    tt: "full",
    tz: "full",
    ts: "partial",
    excel: "none",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.backtestLab,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "none",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.propFirmMode,
    tt: "full",
    tz: "full",
    ts: "partial",
    excel: "none",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.tradingCommunity,
    tt: "full",
    tz: "partial",
    ts: "partial",
    excel: "none",
    discord: "full",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.tradeRooms,
    tt: "full",
    tz: "partial",
    ts: "none",
    excel: "none",
    discord: "partial",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.tradingReels,
    tt: "full",
    tz: "none",
    ts: "none",
    excel: "none",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.directMessaging,
    tt: "full",
    tz: "partial",
    ts: "partial",
    excel: "none",
    discord: "full",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.tradeReplayVideos,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "none",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.unlimitedTradeJournaling,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "partial",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.multipleTradingAccounts,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "partial",
    discord: "none",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.screenshotUploads,
    tt: "full",
    tz: "full",
    ts: "full",
    excel: "partial",
    discord: "partial",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.mobileFriendly,
    tt: "partial",
    tz: "partial",
    ts: "partial",
    excel: "none",
    discord: "partial",
  },
  {
    feature: LANDING_COMPARISON_FEATURE_LABELS.continuousUpdates,
    tt: "full",
    tz: "partial",
    ts: "partial",
    excel: "none",
    discord: "partial",
  },
]

export const LANDING_COMPARISON_COLUMNS = [
  { key: "tt" as const, label: "TradeTraxs", highlight: true },
  { key: "tz" as const, label: "TradeZella", highlight: false },
  { key: "ts" as const, label: "TraderSync", highlight: false },
  { key: "excel" as const, label: "Excel", highlight: false },
  { key: "discord" as const, label: "Discord", highlight: false },
]
