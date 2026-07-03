/**
 * One-time script: create TraxPro Monthly / 6-Month / Yearly Stripe Prices
 * on the existing product (derived from STRIPE_PRICE_ID or STRIPE_PRODUCT_ID).
 *
 * Usage:
 *   STRIPE_SECRET_KEY=sk_... node scripts/create-stripe-traxpro-prices.mjs
 */
import Stripe from "stripe"

const MONTHLY_BASE = 23.99

const PLANS = [
  {
    id: "monthly",
    intervalMonths: 1,
    savePercent: null,
    billingCadenceLabel: "Billed monthly",
    stripePriceEnvKey: "STRIPE_PRICE_ID_MONTHLY",
  },
  {
    id: "six_month",
    intervalMonths: 6,
    savePercent: 5,
    billingCadenceLabel: "Billed every 6 months",
    stripePriceEnvKey: "STRIPE_PRICE_ID_SIX_MONTH",
  },
  {
    id: "yearly",
    intervalMonths: 12,
    savePercent: 15,
    billingCadenceLabel: "Billed annually",
    stripePriceEnvKey: "STRIPE_PRICE_ID_YEARLY",
  },
]

function billedAmount(plan) {
  const multiplier = 1 - (plan.savePercent ?? 0) / 100
  return Math.round(MONTHLY_BASE * plan.intervalMonths * multiplier * 100) / 100
}

function unitAmountCents(plan) {
  return Math.round(billedAmount(plan) * 100)
}

function recurringForPlan(plan) {
  if (plan.intervalMonths === 12) {
    return { interval: "year", interval_count: 1 }
  }
  return { interval: "month", interval_count: plan.intervalMonths }
}

async function resolveProductId(stripe) {
  if (process.env.STRIPE_PRODUCT_ID?.trim()) {
    return process.env.STRIPE_PRODUCT_ID.trim()
  }

  const legacyPriceId = process.env.STRIPE_PRICE_ID?.trim()
  if (!legacyPriceId) {
    throw new Error("Set STRIPE_PRODUCT_ID or STRIPE_PRICE_ID to resolve the TraxPro product.")
  }

  const legacyPrice = await stripe.prices.retrieve(legacyPriceId)
  const product = legacyPrice.product
  if (typeof product !== "string") {
    throw new Error("Could not resolve product id from legacy price.")
  }
  return product
}

async function main() {
  if (!process.env.STRIPE_SECRET_KEY) {
    throw new Error("Missing STRIPE_SECRET_KEY")
  }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY)
  const productId = await resolveProductId(stripe)
  console.log("Using Stripe product:", productId)

  for (const plan of PLANS) {
    const unitAmount = unitAmountCents(plan)
    const billed = billedAmount(plan)
    const recurring = recurringForPlan(plan)

    const price = await stripe.prices.create({
      product: productId,
      currency: "usd",
      unit_amount: unitAmount,
      recurring,
      metadata: {
        billing_interval: plan.id,
        tradetraxs_plan: "traxpro",
      },
    })

    console.log("")
    console.log(`[${plan.id}]`)
    console.log(`  Env: ${plan.stripePriceEnvKey}=${price.id}`)
    console.log(`  Billed: $${billed.toFixed(2)} (${plan.billingCadenceLabel})`)
    console.log(`  Recurring: ${recurring.interval} x ${recurring.interval_count}`)
  }

  console.log("\nAdd the env vars above to your deployment secrets.")
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
