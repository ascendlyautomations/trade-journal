import { TRAXPRO_MONTHLY_LIST_PRICE } from "@/lib/traxProBillingPlans"
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

/** Canonical Pro plan display name (matches Settings + Stripe). */
export const TRAXPRO_PLAN_NAME = TRADETRAXS_PRO_PLAN.name

export const TRAXPRO_PRICE_AMOUNT = TRAXPRO_MONTHLY_LIST_PRICE
export const TRAXPRO_PRICE_DISPLAY = "$23.99"
export const TRAXPRO_BILLING_LABEL = "Billed monthly"
export const TRAXPRO_TRIAL_LABEL = "14-day free trial"

/** Homepage / marketing — anchor monthly price only. */
export const TRAXPRO_PRICE_STARTING_AT = "Starting at $23.99/month"

/** Homepage pricing — price + cadence (derived from canonical amount). */
export const TRAXPRO_PRICE_CADENCE = `${TRAXPRO_PRICE_DISPLAY}/month`

/** Homepage pricing — trial callout headline. */
export const TRAXPRO_TRIAL_HEADLINE = "14-Day Free Trial"

export const TRAXPRO_CHECKOUT_FINE_PRINT =
  "✓ 14-day free trial ✓ Cancel anytime ✓ Billed via Stripe"

/** @deprecated Use {@link TRADETRAXS_FREE_PLAN.features} */
export const LANDING_FREE_FEATURES = TRADETRAXS_FREE_PLAN.features

/** @deprecated Use {@link TRADETRAXS_PRO_PLAN.features} */
export const LANDING_PRO_FEATURES = TRADETRAXS_PRO_PLAN.features

/** @deprecated Use {@link TRADETRAXS_PRO_PLAN.features} */
export const LANDING_PRO_PRICING_HIGHLIGHTS = TRADETRAXS_PRO_PLAN.features
