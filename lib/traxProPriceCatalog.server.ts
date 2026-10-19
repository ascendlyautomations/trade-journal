import { CHECKOUT_TRIAL_ENABLED, CHECKOUT_TRIAL_PERIOD_DAYS } from "@/lib/checkoutTrial"
import { getStripeServer } from "@/lib/stripeServer"
import {
  presentTraxProStripePrices,
  quoteFromStripePrice,
  type TraxProCatalogInterval,
  type TraxProPriceCatalog,
  type TraxProStripePriceInput,
} from "@/lib/traxProPriceCatalog"
import { getVisibleTraxProBillingPlans } from "@/lib/traxProBillingPlans"
import { resolveTraxProStripePriceId } from "@/lib/traxProBillingPlans.server"

const CACHE_MS = 10 * 60 * 1000

let cached: { at: number; signature: string; catalog: TraxProPriceCatalog } | null = null
let pending: Promise<TraxProPriceCatalog> | null = null

export async function loadTraxProStripePriceCatalog(options?: {
  force?: boolean
}): Promise<TraxProPriceCatalog> {
  const signature = catalogSignature()
  if (
    !options?.force &&
    cached &&
    cached.signature === signature &&
    Date.now() - cached.at < CACHE_MS
  ) {
    return cached.catalog
  }
  if (!options?.force && pending) return pending

  pending = readStripeCatalog()
    .then((catalog) => {
      cached = { at: Date.now(), signature, catalog }
      return catalog
    })
    .finally(() => {
      pending = null
    })
  return pending
}

async function readStripeCatalog(): Promise<TraxProPriceCatalog> {
  const stripe = getStripeServer()
  const quotes: TraxProStripePriceInput[] = []
  const unavailable: TraxProCatalogInterval[] = []
  for (const plan of getVisibleTraxProBillingPlans()) {
    if (plan.id === "test") continue
    const interval = plan.id as TraxProCatalogInterval
    let priceId: string
    try {
      priceId = resolveTraxProStripePriceId(plan.id)
    } catch {
      unavailable.push(interval)
      continue
    }
    const price = await stripe.prices.retrieve(priceId)
    const quote = quoteFromStripePrice(interval, price)
    if (!quote || quote.unitAmountCents == null) {
      unavailable.push(interval)
      continue
    }
    quotes.push(quote)
  }
  if (quotes.length === 0) {
    throw new Error("No TraxPro Stripe prices are configured")
  }
  return {
    ...presentTraxProStripePrices(quotes, {
      enabled: CHECKOUT_TRIAL_ENABLED,
      days: CHECKOUT_TRIAL_PERIOD_DAYS,
    }),
    unavailable,
  }
}

function catalogSignature(): string {
  const ids = getVisibleTraxProBillingPlans().map((plan) => {
    try {
      return resolveTraxProStripePriceId(plan.id)
    } catch {
      return ""
    }
  })
  return `${ids.join(",")}|${CHECKOUT_TRIAL_ENABLED}|${CHECKOUT_TRIAL_PERIOD_DAYS}`
}
