import type { TraxProBillingIntervalId } from "./traxProBillingPlans"

/**
 * App Store Connect product identifiers for TraxPro auto-renewable subscriptions.
 *
 * Configure via env so sandbox/production IDs can differ without code changes.
 * Defaults are placeholders — create matching products in App Store Connect before release.
 *
 * All three products MUST belong to the same TraxPro subscription group so Apple
 * handles upgrade/downgrade (monthly ↔ 6-month ↔ yearly) within one entitlement.
 *
 * Apple supports 1, 2, 3, 6, and 12-month auto-renewable durations; our 6-month
 * web plan maps to a 6-month App Store subscription (not a custom duration).
 */
export type TraxProAppleProductKey = "monthly" | "sixMonth" | "yearly"

export type TraxProAppleProductConfig = {
  key: TraxProAppleProductKey
  billingInterval: TraxProBillingIntervalId
  /** App Store Connect product id */
  productId: string
}

const DEFAULT_PRODUCT_IDS: Record<TraxProAppleProductKey, string> = {
  monthly: "com.tradetraxs.traxpro.monthly",
  sixMonth: "com.tradetraxs.traxpro.sixmonth",
  yearly: "com.tradetraxs.traxpro.yearly",
}

const ENV_KEYS: Record<TraxProAppleProductKey, string> = {
  monthly: "APPLE_IAP_PRODUCT_ID_MONTHLY",
  sixMonth: "APPLE_IAP_PRODUCT_ID_SIX_MONTH",
  yearly: "APPLE_IAP_PRODUCT_ID_YEARLY",
}

function readProductId(key: TraxProAppleProductKey): string {
  const envKey = ENV_KEYS[key]
  const fromEnv = process.env[envKey]?.trim()
  return fromEnv && fromEnv.length > 0 ? fromEnv : DEFAULT_PRODUCT_IDS[key]
}

export function getTraxProAppleProducts(): readonly TraxProAppleProductConfig[] {
  return [
    {
      key: "monthly",
      billingInterval: "monthly",
      productId: readProductId("monthly"),
    },
    {
      key: "sixMonth",
      billingInterval: "six_month",
      productId: readProductId("sixMonth"),
    },
    {
      key: "yearly",
      billingInterval: "yearly",
      productId: readProductId("yearly"),
    },
  ] as const
}

export function resolveTraxProBillingIntervalFromAppleProductId(
  productId: string | null | undefined
): TraxProBillingIntervalId | null {
  if (!productId?.trim()) return null
  const normalized = productId.trim()
  for (const product of getTraxProAppleProducts()) {
    if (product.productId === normalized) return product.billingInterval
  }
  return null
}

export function isKnownTraxProAppleProductId(
  productId: string | null | undefined
): boolean {
  return resolveTraxProBillingIntervalFromAppleProductId(productId) != null
}

export function getTraxProAppleProductIdSet(): Set<string> {
  return new Set(getTraxProAppleProducts().map((p) => p.productId))
}
