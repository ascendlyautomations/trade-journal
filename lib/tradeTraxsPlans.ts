/** Canonical TradeTraxs Free & Pro plan copy — single source for all pricing surfaces. */

export type TradeTraxsPlanId = "free" | "pro"

export type TradeTraxsPlan = {
  id: TradeTraxsPlanId
  name: string
  description: string
  features: readonly string[]
  /** Label above the feature list (Pro: incremental value over Free). */
  featuresHeading?: string
}

export const TRADETRAXS_FREE_PLAN: TradeTraxsPlan = {
  id: "free",
  name: "TradeTraxs Free",
  description:
    "Get started with TradeTraxs by tracking your trades, exploring the community, and discovering what makes your trading unique.",
  features: [
    "Manual Trade Journaling",
    "Community Feed",
    "Trade Rooms",
    "Public & Private Profiles",
    "Basic Trading Statistics",
    "Up to 5 Trades Per Day",
  ],
}

/** Pro feature list heading — shown above incremental Pro features on pricing surfaces. */
export const TRADETRAXS_PRO_FEATURES_HEADING = "Everything in Free, plus:"

export const TRADETRAXS_PRO_PLAN: TradeTraxsPlan = {
  id: "pro",
  name: "TradeTraxs Pro",
  description:
    "Unlock the complete TradeTraxs experience with unlimited journaling, professional analytics, AI-powered insights, and every premium feature designed to help you become a more consistent trader.",
  featuresHeading: TRADETRAXS_PRO_FEATURES_HEADING,
  features: [
    "Unlimited Trade Journaling",
    "Advanced Performance Analytics",
    "AI Trade Analyst",
    "Backtest Lab",
    "Prop Firm Mode",
    "Trade Replay Videos",
    "Unlimited Screenshot Uploads",
    "Unlimited Trading Accounts",
    "Advanced Trade Insights & Performance Reports",
    "Priority Access to New Features",
  ],
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
