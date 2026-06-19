import { FREE_PLAN_TRADES_PER_24H } from "@/lib/freePlanLimits"

/** Canonical TraxPro marketing / billing copy (matches Stripe + Settings). */
export const TRAXPRO_PLAN_NAME = "TraxPro"
export const TRAXPRO_PRICE_AMOUNT = 23.99
export const TRAXPRO_PRICE_DISPLAY = "$23.99"
export const TRAXPRO_BILLING_LABEL = "Billed every 4 weeks"
export const TRAXPRO_TRIAL_LABEL = "14-day free trial"

export const TRAXPRO_CHECKOUT_FINE_PRINT =
  "✓ 14-day free trial ✓ Cancel anytime ✓ Billed every 4 weeks via Stripe"

/** Homepage + /pricing Free tier (aligned with product gates). */
export const LANDING_FREE_FEATURES = [
  `Track trades (up to ${FREE_PLAN_TRADES_PER_24H} per 24 hours)`,
  "1 trading account",
  "Limited dashboard insights",
  "Trading calendar",
  "Public profile & community feed",
  "1 CSV import",
  "Messaging & comments (10 per 24 hours)",
  "1 public trade share & 1 feed post per 24 hours",
] as const

/** Homepage + /pricing TraxPro tier (aligned with product gates). */
export const LANDING_PRO_FEATURES = [
  "Unlimited trading accounts",
  "Unlimited trade logging",
  "Full performance dashboard & advanced insights",
  "AI Trade Analyst",
  "Unlimited CSV import",
  "Full messaging & comments",
  "Session + strategy breakdowns",
  "Prop Firm Mode analytics",
] as const
