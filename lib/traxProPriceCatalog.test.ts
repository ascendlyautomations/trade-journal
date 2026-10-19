import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  presentTraxProStripePrices,
  publicTraxProPriceResponse,
  quoteFromStripePrice,
  traxProPostTrialFootnote,
  traxProTrialPresentation,
  type TraxProStripePriceInput,
} from "./traxProPriceCatalog.ts"

const formulaPrices: TraxProStripePriceInput[] = [
  {
    interval: "monthly",
    unitAmountCents: 2399,
    currency: "usd",
    recurringInterval: "month",
    intervalCount: 1,
  },
  {
    interval: "six_month",
    unitAmountCents: 13674,
    currency: "usd",
    recurringInterval: "month",
    intervalCount: 6,
  },
  {
    interval: "yearly",
    unitAmountCents: 24470,
    currency: "usd",
    recurringInterval: "year",
    intervalCount: 1,
  },
]

describe("Stripe price presentation", () => {
  it("shows cycle total, monthly equivalent, and a discount only when the prices support it", () => {
    const catalog = presentTraxProStripePrices(formulaPrices, {
      enabled: true,
      days: 14,
    })
    const monthly = catalog.plans.find((plan) => plan.interval === "monthly")
    const six = catalog.plans.find((plan) => plan.interval === "six_month")
    const yearly = catalog.plans.find((plan) => plan.interval === "yearly")
    assert.equal(monthly?.totalLabel, "$23.99")
    assert.equal(monthly?.equivalentMonthlyLabel, "$23.99/mo")
    assert.equal(monthly?.periodLabel, "Monthly")
    assert.equal(monthly?.savePercent, null)
    assert.equal(six?.totalLabel, "$136.74")
    assert.equal(six?.equivalentMonthlyLabel, "$22.79/mo")
    assert.equal(six?.periodLabel, "6 months")
    assert.equal(six?.billingCadenceLabel, "Billed every 6 months")
    assert.equal(six?.savePercent, 5)
    assert.equal(yearly?.totalLabel, "$244.70")
    assert.equal(yearly?.periodLabel, "Yearly")
    assert.equal(yearly?.savePercent, 15)
    assert.equal(catalog.trialDays, 14)
    assert.deepEqual(catalog.unavailable, [])
  })

  it("does not advertise a discount when every cycle is the monthly price", () => {
    const catalog = presentTraxProStripePrices(
      [
        formulaPrices[0],
        {
          interval: "six_month",
          unitAmountCents: 2399 * 6,
          currency: "usd",
          recurringInterval: "month",
          intervalCount: 6,
        },
      ],
      { enabled: true, days: 14 }
    )
    const six = catalog.plans.find((plan) => plan.interval === "six_month")
    assert.equal(six?.savePercent, null)
    assert.equal(six?.checkoutOptionLabel, "6 months")
  })

  it("shows a 4-week Stripe price as 4 weeks and does not invent a monthly discount", () => {
    const catalog = presentTraxProStripePrices(
      [
        {
          interval: "monthly",
          unitAmountCents: 2399,
          currency: "usd",
          recurringInterval: "week",
          intervalCount: 4,
        },
        formulaPrices[1],
        formulaPrices[2],
      ],
      { enabled: true, days: 14 }
    )
    const monthly = catalog.plans.find((plan) => plan.interval === "monthly")
    assert.equal(monthly?.periodLabel, "4 weeks")
    assert.equal(monthly?.billingCadenceLabel, "Billed every 4 weeks")
    assert.equal(monthly?.totalLabel, "$23.99")
    assert.equal(monthly?.equivalentMonthlyLabel, null)
    assert.equal(monthly?.aligned, false)
    assert.equal(catalog.plans.find((plan) => plan.interval === "six_month")?.savePercent, null)
    assert.equal(catalog.plans.find((plan) => plan.interval === "yearly")?.savePercent, null)
  })

  it("uses the Stripe period when a price is not the configured interval", () => {
    const catalog = presentTraxProStripePrices(
      [
        {
          interval: "yearly",
          unitAmountCents: 2399,
          currency: "usd",
          recurringInterval: "month",
          intervalCount: 1,
        },
      ],
      { enabled: false, days: 14 }
    )
    const plan = catalog.plans[0]
    assert.equal(plan?.aligned, false)
    assert.equal(plan?.periodLabel, "Monthly")
    assert.equal(plan?.checkoutOptionLabel, "Monthly")
    assert.equal(plan?.savePercent, null)
    assert.equal(catalog.trialDays, null)
  })

  it("describes the configured Stripe trial and omits it when checkout will not grant one", () => {
    const eligible = traxProTrialPresentation(14)
    assert.equal(eligible.offerSummary, "14 days free trial")
    assert.equal(eligible.buttonTitle, "Start 14-Day Free Trial")
    assert.match(eligible.finePrint, /14 days free trial/)
    const ineligible = traxProTrialPresentation(null)
    assert.equal(ineligible.buttonTitle, "Upgrade to Pro")
    assert.equal(ineligible.offerSummary, null)
    assert.doesNotMatch(ineligible.finePrint, /trial/i)
    const plan = presentTraxProStripePrices(formulaPrices, {
      enabled: true,
      days: 14,
    }).plans[0]
    assert.equal(
      traxProPostTrialFootnote(plan ?? null, 14),
      "Then $23.99, billed monthly. Cancel anytime."
    )
    assert.equal(traxProPostTrialFootnote(plan ?? null, null), null)
  })

  it("keeps the public payload free of Stripe secrets and price ids", () => {
    const quote = quoteFromStripePrice("monthly", {
      unit_amount: 2399,
      currency: "usd",
      recurring: { interval: "month", interval_count: 1 },
    })
    assert.ok(quote)
    const body = publicTraxProPriceResponse(
      presentTraxProStripePrices([quote!], { enabled: true, days: 7 })
    )
    const encoded = JSON.stringify(body)
    assert.equal(body.trialDays, 7)
    assert.doesNotMatch(encoded, /sk_live|sk_test|price_/i)
  })
})
