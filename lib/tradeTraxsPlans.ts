/** Canonical TradeTraxs Free & TraxPro plan copy — single source for all pricing surfaces. */

import {
  FREE_PLAN_ACTIVE_TRADING_ACCOUNTS_LABEL,
  FREE_PLAN_BROKER_INTEGRATIONS_LABEL,
  FREE_PLAN_DAILY_CLIP_PRICING_LABEL,
  FREE_PLAN_UNLIMITED_CSV_IMPORTS_LABEL,
  FREE_PLAN_UNLIMITED_MANUAL_TRADES_LABEL,
  FREE_PLAN_UNLIMITED_POSTS_LABEL,
} from "./freePlanDailyLimits.ts"
import {
  FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL,
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
  featuresHeading?: string
  featureGroups?: readonly TradeTraxsPlanFeatureGroup[]
}

export const TRADETRAXS_FEATURE_LABELS = {
  basicAnalytics: "Basic Dashboard & core performance analytics",
  premiumAnalytics: "Advanced performance analytics",
  unlimitedTradingAccounts: "Unlimited active trading accounts",
  unlimitedClips: "Unlimited Clips",
  aiTradeAnalyst: "AI Trade Analyst",
  aiPsychologyCoach: "AI Psychology Coach",
  aiTradeAnalystAndCoach: "AI Trade Analyst & Psychology Coach",
  weeklyMonthlyReports: "Trading reports",
  backtestLab: "Backtest Lab",
  advancedPropFirmAnalytics: "Advanced Prop Firm Analytics",
  copyTradingGroups: "Copy Trading",
  copyTradingGroupsDetail:
    "Automatically journal the same trade across multiple accounts",
} as const

/** @deprecated Prefer {@link TRADETRAXS_FEATURE_LABELS}. */
export const TRADETRAXS_PRO_FEATURE_LABELS = {
  ...TRADETRAXS_FEATURE_LABELS,
  propFirmMode: TRADETRAXS_FEATURE_LABELS.advancedPropFirmAnalytics,
  weeklyReports: "Trading reports",
  monthlyReports: "Trading reports",
  advancedPerformanceInsights: TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
} as const

export const TRADETRAXS_FREE_PLAN: TradeTraxsPlan = {
  id: "free",
  name: "TradeTraxs Free",
  description:
    "Generous journaling, CSV imports, broker connections, community, and core analytics. No credit card required.",
  features: [
    FREE_PLAN_UNLIMITED_MANUAL_TRADES_LABEL,
    FREE_PLAN_UNLIMITED_CSV_IMPORTS_LABEL,
    FREE_PLAN_BROKER_INTEGRATIONS_LABEL,
    FREE_PLAN_ACTIVE_TRADING_ACCOUNTS_LABEL,
    FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL,
    FREE_PLAN_UNLIMITED_POSTS_LABEL,
    FREE_PLAN_DAILY_CLIP_PRICING_LABEL,
    FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL,
    TRADETRAXS_FEATURE_LABELS.basicAnalytics,
    "Psychology check-ins & payout recording",
    "Feed, Explore, profiles, Vault, leaderboards",
    "Posts, Clips, stories, achievements",
    "Following, comments, likes & sharing",
  ],
}

export const TRADETRAXS_PRO_FEATURES_HEADING = "Everything in Free, plus:"

export const TRADETRAXS_PRO_FEATURE_GROUPS: readonly TradeTraxsPlanFeatureGroup[] =
  [
    {
      heading: "TraxPro",
      features: [
        TRADETRAXS_FEATURE_LABELS.unlimitedTradingAccounts,
        TRADETRAXS_FEATURE_LABELS.advancedPropFirmAnalytics,
        TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
        TRADETRAXS_FEATURE_LABELS.aiTradeAnalystAndCoach,
        TRADETRAXS_FEATURE_LABELS.weeklyMonthlyReports,
        TRADETRAXS_FEATURE_LABELS.backtestLab,
        TRADETRAXS_FEATURE_LABELS.copyTradingGroups,
        TRADETRAXS_FEATURE_LABELS.unlimitedClips,
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
  name: "TraxPro",
  description:
    "Powerful tools for serious traders — unlimited accounts and Clips, advanced analytics, AI coaching, reports, Backtest Lab, and Copy Trading.",
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

export function formatPlanFeaturesList(
  plan: TradeTraxsPlan,
  separator = ", "
): string {
  return plan.features.join(separator)
}

export function getPlanFeaturesSectionHeading(
  planId: TradeTraxsPlanId
): string {
  if (planId === "pro") return TRADETRAXS_PRO_FEATURES_HEADING
  return "Included Features"
}
