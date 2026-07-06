/**
 * "Nothing Else Comes Close" comparison — audited feature rows.
 *
 * TradeTraxs (tt): platform capability (Pro unlocks premium analytics, AI, etc.).
 * Other Journals: conservative rollup of typical trading-journal apps (audited 2026).
 * Excel / Notion: spreadsheet / notes workflows.
 *
 * Wording aligns with {@link TRADETRAXS_PRO_PLAN} / pricing page where applicable.
 */

import {
  TRADETRAXS_FEATURE_LABELS,
  TRADETRAXS_PRO_FEATURE_LABELS,
} from "./tradeTraxsPlans.ts"

export type ComparisonTriState = "full" | "partial" | "none"

export type LandingComparisonColumnKey = "tt" | "otherJournals" | "excelNotion"

export type LandingComparisonRow = {
  id: string
  feature: string
  tt: ComparisonTriState
  otherJournals: ComparisonTriState
  excelNotion: ComparisonTriState
}

export const LANDING_COMPARISON_SUBTITLE =
  "TradeTraxs combines powerful analytics, AI-powered insights, social trading, and professional journaling into one complete platform—something most trading journals simply don't offer."

export const LANDING_COMPARISON_MOBILE_PREVIEW_COUNT = 3

/** Benefit-focused labels — strongest differentiators first. */
export const LANDING_COMPARISON_FEATURE_LABELS = {
  aiTradeAnalyst: TRADETRAXS_PRO_FEATURE_LABELS.aiTradeAnalyst,
  propFirmMode: TRADETRAXS_PRO_FEATURE_LABELS.propFirmMode,
  communityTradeRooms: "Community & Trade Rooms",
  performanceAnalytics: TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
  brandedShareCards: TRADETRAXS_FEATURE_LABELS.performanceImageExports,
  backtestLab: TRADETRAXS_PRO_FEATURE_LABELS.backtestLab,
  unlimitedTradeJournaling: TRADETRAXS_PRO_FEATURE_LABELS.unlimitedTrades,
  multipleTradingAccounts: TRADETRAXS_PRO_FEATURE_LABELS.unlimitedTradingAccounts,
  screenshotUploads: "Screenshot Uploads",
  tradingReels: "Trading Clips",
  directMessaging: "Direct Messaging",
  continuousUpdates: "Continuous Feature Updates",
} as const

export const LANDING_COMPARISON_ROWS: readonly LandingComparisonRow[] = [
  {
    id: "ai-trade-analyst",
    feature: LANDING_COMPARISON_FEATURE_LABELS.aiTradeAnalyst,
    tt: "full",
    otherJournals: "partial",
    excelNotion: "none",
  },
  {
    id: "prop-firm-mode",
    feature: LANDING_COMPARISON_FEATURE_LABELS.propFirmMode,
    tt: "full",
    otherJournals: "none",
    excelNotion: "none",
  },
  {
    id: "community-trade-rooms",
    feature: LANDING_COMPARISON_FEATURE_LABELS.communityTradeRooms,
    tt: "full",
    otherJournals: "none",
    excelNotion: "none",
  },
  {
    id: "performance-analytics",
    feature: LANDING_COMPARISON_FEATURE_LABELS.performanceAnalytics,
    tt: "full",
    otherJournals: "full",
    excelNotion: "partial",
  },
  {
    id: "branded-share-cards",
    feature: LANDING_COMPARISON_FEATURE_LABELS.brandedShareCards,
    tt: "full",
    otherJournals: "none",
    excelNotion: "none",
  },
  {
    id: "backtest-lab",
    feature: LANDING_COMPARISON_FEATURE_LABELS.backtestLab,
    tt: "full",
    otherJournals: "full",
    excelNotion: "none",
  },
  {
    id: "unlimited-trade-journaling",
    feature: LANDING_COMPARISON_FEATURE_LABELS.unlimitedTradeJournaling,
    tt: "full",
    otherJournals: "full",
    excelNotion: "partial",
  },
  {
    id: "unlimited-trading-accounts",
    feature: LANDING_COMPARISON_FEATURE_LABELS.multipleTradingAccounts,
    tt: "full",
    otherJournals: "full",
    excelNotion: "partial",
  },
  {
    id: "screenshot-uploads",
    feature: LANDING_COMPARISON_FEATURE_LABELS.screenshotUploads,
    tt: "full",
    otherJournals: "full",
    excelNotion: "partial",
  },
  {
    id: "trading-reels",
    feature: LANDING_COMPARISON_FEATURE_LABELS.tradingReels,
    tt: "full",
    otherJournals: "none",
    excelNotion: "none",
  },
  {
    id: "direct-messaging",
    feature: LANDING_COMPARISON_FEATURE_LABELS.directMessaging,
    tt: "full",
    otherJournals: "none",
    excelNotion: "none",
  },
  {
    id: "continuous-updates",
    feature: LANDING_COMPARISON_FEATURE_LABELS.continuousUpdates,
    tt: "full",
    otherJournals: "partial",
    excelNotion: "none",
  },
]

export const LANDING_COMPARISON_COLUMNS = [
  { key: "tt" as const, label: "TradeTraxs", highlight: true },
  { key: "otherJournals" as const, label: "Other Journals", highlight: false },
  { key: "excelNotion" as const, label: "Excel / Notion", highlight: false },
] as const

export function comparisonStateEmoji(state: ComparisonTriState): string {
  if (state === "full") return "✅"
  if (state === "partial") return "⚠️"
  return "❌"
}

export function comparisonStateLabel(state: ComparisonTriState): string {
  if (state === "full") return "Included"
  if (state === "partial") return "Limited"
  return "Not Included"
}

export function getComparisonCellState(
  row: LandingComparisonRow,
  columnKey: LandingComparisonColumnKey
): ComparisonTriState {
  return row[columnKey]
}
