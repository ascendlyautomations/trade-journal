/** Canonical TradeTraxs Free & Pro plan copy — single source for all pricing surfaces. */

import {
  FREE_PLAN_DAILY_CLIP_PRICING_LABEL,
  FREE_PLAN_DAILY_POST_PRICING_LABEL,
  FREE_PLAN_DAILY_TRADE_PRICING_LABEL,
} from "./freePlanDailyLimits.ts"
import {
  FREE_PLAN_DAILY_DM_PRICING_LABEL,
  FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL,
} from "./freePlanMessagingLimits.ts"

export type TradeTraxsPlanId = "free" | "pro"

export type TradeTraxsPlanFeatureGroup = {
  heading: string
  features: readonly string[]
}

export type TradeTraxsPlan = {
  id: TradeTraxsPlanId
  name: string
  description: string
  features: readonly string[]
  /** Label above the feature list (Pro: incremental value over Free). */
  featuresHeading?: string
  /** Grouped Pro features for pricing cards (headings + bullets). */
  featureGroups?: readonly TradeTraxsPlanFeatureGroup[]
}

/** Stable labels referenced by marketing comparison tables. */
export const TRADETRAXS_FEATURE_LABELS = {
  basicAnalytics: "Basic Analytics",
  premiumAnalytics: "Premium Analytics & Performance Insights",
  unlimitedTrades: "Unlimited Trades",
  unlimitedDirectMessages: "Unlimited Direct Messages",
  unlimitedTradingAccounts: "Unlimited Trading Accounts",
  csvImport: "CSV Import",
  aiTradeAnalyst: "AI Analyst",
  weeklyMonthlyReports: "Weekly & Monthly Trading Reports",
  backtestLab: "Backtest Lab",
  propFirmMode: "Prop Firm Mode",
  performanceImageExports: "Performance Image Exports",
  copyTradingGroups: "Copy Trading Groups",
  copyTradingGroupsDetail: "Automatically journal the same trade across multiple accounts",
} as const

/** @deprecated Prefer {@link TRADETRAXS_FEATURE_LABELS}. */
export const TRADETRAXS_PRO_FEATURE_LABELS = {
  ...TRADETRAXS_FEATURE_LABELS,
  weeklyReports: "Weekly Reports",
  monthlyReports: "Monthly Reports",
  profitFactor: "Profit Factor",
  brandedShareCards: "Branded Share Cards",
  advancedPerformanceInsights: TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
} as const

export const TRADETRAXS_FREE_PLAN: TradeTraxsPlan = {
  id: "free",
  name: "TradeTraxs Free",
  description:
    "Track trades manually, explore the community, and review core performance stats — no credit card required.",
  features: [
    FREE_PLAN_DAILY_TRADE_PRICING_LABEL,
    FREE_PLAN_DAILY_POST_PRICING_LABEL,
    FREE_PLAN_DAILY_CLIP_PRICING_LABEL,
    FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL,
    FREE_PLAN_DAILY_DM_PRICING_LABEL,
    "Manual Trade Entry",
    TRADETRAXS_FEATURE_LABELS.basicAnalytics,
    "Basic Calendar",
    "Public & Private Profiles",
    "Feed, Posts & Clips",
    "Following, Comments & Likes",
    "Public Trade Sharing",
  ],
}

/** Pro feature list heading — shown above incremental Pro features on pricing surfaces. */
export const TRADETRAXS_PRO_FEATURES_HEADING = "Everything in Free, plus:"

export const TRADETRAXS_PRO_FEATURE_GROUPS: readonly TradeTraxsPlanFeatureGroup[] =
  [
    {
      heading: "Unlimited Trading",
      features: [
        TRADETRAXS_FEATURE_LABELS.unlimitedTrades,
        TRADETRAXS_FEATURE_LABELS.unlimitedTradingAccounts,
        TRADETRAXS_FEATURE_LABELS.csvImport,
        TRADETRAXS_FEATURE_LABELS.unlimitedDirectMessages,
      ],
    },
    {
      heading: "AI Tools",
      features: [
        TRADETRAXS_FEATURE_LABELS.aiTradeAnalyst,
        TRADETRAXS_FEATURE_LABELS.weeklyMonthlyReports,
      ],
    },
    {
      heading: "Advanced Analytics",
      features: [TRADETRAXS_FEATURE_LABELS.premiumAnalytics],
    },
    {
      heading: "Professional Tools",
      features: [
        TRADETRAXS_FEATURE_LABELS.backtestLab,
        TRADETRAXS_FEATURE_LABELS.propFirmMode,
        TRADETRAXS_FEATURE_LABELS.performanceImageExports,
        TRADETRAXS_FEATURE_LABELS.copyTradingGroups,
        TRADETRAXS_FEATURE_LABELS.copyTradingGroupsDetail,
      ],
    },
    {
      heading: "Everything in Free",
      features: [],
    },
  ]

function flattenProFeatureGroups(
  groups: readonly TradeTraxsPlanFeatureGroup[]
): string[] {
  return groups.flatMap((group) => [...group.features])
}

export const TRADETRAXS_PRO_PLAN: TradeTraxsPlan = {
  id: "pro",
  name: "TradeTraxs Pro",
  description:
    "Unlock unlimited journaling, AI-powered analysis, premium analytics, and professional tools built to help you trade with consistency.",
  featuresHeading: TRADETRAXS_PRO_FEATURES_HEADING,
  featureGroups: TRADETRAXS_PRO_FEATURE_GROUPS,
  features: flattenProFeatureGroups(TRADETRAXS_PRO_FEATURE_GROUPS),
}

const PLANS: Record<TradeTraxsPlanId, TradeTraxsPlan> = {
  free: TRADETRAXS_FREE_PLAN,
  pro: TRADETRAXS_PRO_PLAN,
}

export function getTradeTraxsPlan(id: TradeTraxsPlanId): TradeTraxsPlan {
  return PLANS[id]
}

/** Comma- or semicolon-separated feature list for FAQ / prose. */
export function formatPlanFeaturesList(
  plan: TradeTraxsPlan,
  separator = ", "
): string {
  return plan.features.join(separator)
}

/** Settings / subscription section label above the active plan's feature list. */
export function getPlanFeaturesSectionHeading(
  planId: TradeTraxsPlanId
): string {
  if (planId === "pro") return TRADETRAXS_PRO_FEATURES_HEADING
  return "Included Features"
}
