/** Canonical TraxPro marketing / billing copy (matches Stripe + Settings). */
export const TRAXPRO_PLAN_NAME = "TraxPro"
export const TRAXPRO_PRICE_AMOUNT = 23.99
export const TRAXPRO_PRICE_DISPLAY = "$23.99"
export const TRAXPRO_BILLING_LABEL = "Billed every 4 weeks"
export const TRAXPRO_TRIAL_LABEL = "14-day free trial"

/** Homepage pricing — price + cadence (derived from canonical amount). */
export const TRAXPRO_PRICE_CADENCE = `${TRAXPRO_PRICE_DISPLAY} every 4 weeks`

/** Homepage pricing — trial callout headline. */
export const TRAXPRO_TRIAL_HEADLINE = "14-Day Free Trial"

export const TRAXPRO_CHECKOUT_FINE_PRINT =
  "✓ 14-day free trial ✓ Cancel anytime ✓ Billed every 4 weeks via Stripe"

/** Homepage + /pricing Free tier (aligned with product gates). */
export const LANDING_FREE_FEATURES = [
  "3 Trading Accounts",
  "Unlimited Trades",
  "Basic Analytics",
  "Community Access",
  "Rooms & Messaging",
  "1 CSV Import",
] as const

/** Homepage + /pricing TraxPro tier (aligned with product gates). */
export const LANDING_PRO_FEATURES = [
  "Unlimited Accounts",
  "AI Trade Analyst",
  "Backtest Lab",
  "Prop Firm Dashboard",
  "Advanced Analytics",
  "Unlimited CSV Imports",
] as const

/** Homepage V2 pricing card — TraxPro highlights. */
export const LANDING_PRO_PRICING_HIGHLIGHTS = [
  "Unlimited trades",
  "Advanced Analytics",
  "AI Analyst",
  "Prop Firm Dashboard",
  "Backtest Lab",
  "Priority Features",
] as const
