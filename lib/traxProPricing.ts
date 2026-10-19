import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"

export {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
  TRADETRAXS_PRO_FEATURES_HEADING,
  getTradeTraxsPlan,
  getPlanFeaturesSectionHeading,
  formatPlanFeaturesList,
  type TradeTraxsPlan,
  type TradeTraxsPlanId,
} from "@/lib/tradeTraxsPlans"

/** Canonical Pro plan display name. Purchase amounts come from the Stripe price catalog. */
export const TRAXPRO_PLAN_NAME = TRADETRAXS_PRO_PLAN.name

/** @deprecated Use {@link TRADETRAXS_FREE_PLAN.features} */
export const LANDING_FREE_FEATURES = TRADETRAXS_FREE_PLAN.features

/** @deprecated Use {@link TRADETRAXS_PRO_PLAN.features} */
export const LANDING_PRO_FEATURES = TRADETRAXS_PRO_PLAN.features

/** @deprecated Use {@link TRADETRAXS_PRO_PLAN.features} */
export const LANDING_PRO_PRICING_HIGHLIGHTS = TRADETRAXS_PRO_PLAN.features
