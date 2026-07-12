import {
  getTraxProBillingPlan,
  isTraxProBillingIntervalId,
  isTraxProTestPlanEnabled,
  TRAXPRO_BILLING_PLANS,
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  TRAXPRO_TEST_BILLING_PLAN,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"

const LEGACY_STRIPE_PRICE_ENV = "STRIPE_PRICE_ID"

function readEnvPriceId(key: string): string | null {
  const value = process.env[key]?.trim()
  return value || null
}

/** Resolve Stripe Price ID for a billing interval (server-only). */
export function resolveTraxProStripePriceId(
  interval: TraxProBillingIntervalId = TRAXPRO_DEFAULT_BILLING_INTERVAL
): string {
  if (interval === "test" && !isTraxProTestPlanEnabled()) {
    throw new Error("Test Plan is not configured (set STRIPE_PRICE_ID_TEST)")
  }

  const plan = getTraxProBillingPlan(interval)
  const priceId = readEnvPriceId(plan.stripePriceEnvKey)
  if (priceId) return priceId

  if (interval === TRAXPRO_DEFAULT_BILLING_INTERVAL) {
    const legacy = readEnvPriceId(LEGACY_STRIPE_PRICE_ENV)
    if (legacy) return legacy
  }

  throw new Error(
    `Missing Stripe price env for ${interval} (set ${plan.stripePriceEnvKey})`
  )
}

/** Map a Stripe Price ID back to a billing interval when possible. */
export function resolveTraxProBillingIntervalFromStripePriceId(
  priceId: string | null | undefined
): TraxProBillingIntervalId | null {
  if (!priceId?.trim()) return null
  const normalized = priceId.trim()

  for (const plan of TRAXPRO_BILLING_PLANS) {
    const envPrice = readEnvPriceId(plan.stripePriceEnvKey)
    if (envPrice && envPrice === normalized) return plan.id
  }

  // TEMPORARY — live Stripe test plan
  const testPrice = readEnvPriceId(TRAXPRO_TEST_BILLING_PLAN.stripePriceEnvKey)
  if (testPrice && testPrice === normalized) return "test"

  const legacy = readEnvPriceId(LEGACY_STRIPE_PRICE_ENV)
  if (legacy && legacy === normalized) return TRAXPRO_DEFAULT_BILLING_INTERVAL

  return null
}

export function parseCheckoutBillingInterval(
  body: unknown
): TraxProBillingIntervalId {
  if (!body || typeof body !== "object") return TRAXPRO_DEFAULT_BILLING_INTERVAL

  const record = body as Record<string, unknown>
  const raw =
    record.billingInterval ?? record.billing_interval ?? record.interval

  if (isTraxProBillingIntervalId(raw)) {
    // TEMPORARY — reject Test Plan checkout when env is not configured
    if (raw === "test" && !isTraxProTestPlanEnabled()) {
      return TRAXPRO_DEFAULT_BILLING_INTERVAL
    }
    return raw
  }
  return TRAXPRO_DEFAULT_BILLING_INTERVAL
}
