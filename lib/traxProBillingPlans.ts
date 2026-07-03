/** TraxPro billing interval registry — extend {@link TRAXPRO_BILLING_PLANS} for new cadences. */

export type TraxProBillingIntervalId = "monthly" | "six_month" | "yearly"

export type TraxProBillingPlan = {
  id: TraxProBillingIntervalId
  /** Short label for settings / billing */
  label: string
  /** Settings subscription card — e.g. "Monthly Plan" */
  settingsPlanLabel: string
  /** Settings subscription card — e.g. "Monthly" under "Billed:" */
  settingsBilledLabel: string
  /** Radio option label in checkout UI */
  checkoutOptionLabel: string
  /** Months billed per Stripe renewal cycle */
  intervalMonths: number
  /** Percent saved vs paying monthly list price (null = anchor plan) */
  savePercent: number | null
  bestValue?: boolean
  /** Human-readable billing cadence under effective price */
  billingCadenceLabel: string
  /** Env var holding the Stripe Price ID (server-side) */
  stripePriceEnvKey:
    | "STRIPE_PRICE_ID_MONTHLY"
    | "STRIPE_PRICE_ID_SIX_MONTH"
    | "STRIPE_PRICE_ID_YEARLY"
}

/** Canonical monthly list price — all intervals derive from this. */
export const TRAXPRO_MONTHLY_LIST_PRICE = 23.99

export const TRAXPRO_PRODUCT_DISPLAY_NAME = "TradeTraxs Pro"

export const TRAXPRO_BILLING_PLANS: readonly TraxProBillingPlan[] = [
  {
    id: "monthly",
    label: "Monthly",
    settingsPlanLabel: "Monthly Plan",
    settingsBilledLabel: "Monthly",
    checkoutOptionLabel: "Monthly",
    intervalMonths: 1,
    savePercent: null,
    billingCadenceLabel: "Billed monthly",
    stripePriceEnvKey: "STRIPE_PRICE_ID_MONTHLY",
  },
  {
    id: "six_month",
    label: "6 Months",
    settingsPlanLabel: "6-Month Plan",
    settingsBilledLabel: "Every 6 Months",
    checkoutOptionLabel: "6 Months — Save 5%",
    intervalMonths: 6,
    savePercent: 5,
    billingCadenceLabel: "Billed every 6 months",
    stripePriceEnvKey: "STRIPE_PRICE_ID_SIX_MONTH",
  },
  {
    id: "yearly",
    label: "Yearly",
    settingsPlanLabel: "Yearly Plan",
    settingsBilledLabel: "Annually",
    checkoutOptionLabel: "Yearly ⭐ Save 15%",
    intervalMonths: 12,
    savePercent: 15,
    bestValue: true,
    billingCadenceLabel: "Billed annually",
    stripePriceEnvKey: "STRIPE_PRICE_ID_YEARLY",
  },
] as const

export const TRAXPRO_DEFAULT_BILLING_INTERVAL: TraxProBillingIntervalId = "monthly"

const planById = new Map(
  TRAXPRO_BILLING_PLANS.map((plan) => [plan.id, plan] as const)
)

export function isTraxProBillingIntervalId(
  value: unknown
): value is TraxProBillingIntervalId {
  return typeof value === "string" && planById.has(value as TraxProBillingIntervalId)
}

export function getTraxProBillingPlan(
  id: TraxProBillingIntervalId
): TraxProBillingPlan {
  const plan = planById.get(id)
  if (!plan) {
    throw new Error(`Unknown TraxPro billing interval: ${id}`)
  }
  return plan
}

export function roundCurrency(amount: number): number {
  return Math.round(amount * 100) / 100
}

export function getTraxProPlanEffectiveMonthlyAmount(plan: TraxProBillingPlan): number {
  if (plan.savePercent == null) return TRAXPRO_MONTHLY_LIST_PRICE
  return roundCurrency(
    TRAXPRO_MONTHLY_LIST_PRICE * (1 - plan.savePercent / 100)
  )
}

/** Total charged each Stripe billing cycle (before trial). */
export function getTraxProPlanBilledAmount(plan: TraxProBillingPlan): number {
  const multiplier = 1 - (plan.savePercent ?? 0) / 100
  return roundCurrency(TRAXPRO_MONTHLY_LIST_PRICE * plan.intervalMonths * multiplier)
}

export function formatTraxProCurrency(amount: number): string {
  return `$${amount.toFixed(2)}`
}

export function formatTraxProEffectiveMonthly(plan: TraxProBillingPlan): string {
  return `${formatTraxProCurrency(getTraxProPlanEffectiveMonthlyAmount(plan))}/mo`
}

export function formatTraxProBillingIntervalLabel(
  interval: TraxProBillingIntervalId | string | null | undefined
): string | null {
  if (!interval || !isTraxProBillingIntervalId(interval)) return null
  return getTraxProBillingPlan(interval).label
}

/** Settings / subscription plan line, e.g. "TraxPro (Monthly)". */
export function formatTraxProSubscriptionPlanLine(
  interval: TraxProBillingIntervalId | string | null | undefined
): string {
  const label = formatTraxProBillingIntervalLabel(interval)
  if (label) return `TraxPro (${label})`
  return "TraxPro"
}

export type TraxProSubscriptionDisplay = {
  productName: string
  planLabel: string | null
  billedLabel: string | null
}

/** Settings subscription card — product + interval from profile billing_interval. */
export function getTraxProSubscriptionDisplay(
  interval: TraxProBillingIntervalId | string | null | undefined
): TraxProSubscriptionDisplay {
  if (!interval || !isTraxProBillingIntervalId(interval)) {
    return {
      productName: TRAXPRO_PRODUCT_DISPLAY_NAME,
      planLabel: null,
      billedLabel: null,
    }
  }

  const plan = getTraxProBillingPlan(interval)
  return {
    productName: TRAXPRO_PRODUCT_DISPLAY_NAME,
    planLabel: plan.settingsPlanLabel,
    billedLabel: plan.settingsBilledLabel,
  }
}

export function getTraxProPlanStripeUnitAmountCents(plan: TraxProBillingPlan): number {
  return Math.round(getTraxProPlanBilledAmount(plan) * 100)
}
