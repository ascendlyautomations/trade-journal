const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  COMMISSION_RATE,
  calculateAffiliateCommission,
  centsToMajorUnits,
  extractStripePriceIdFromInvoice,
  resolveAffiliateCommissionBaseCents,
} = require("./affiliateEarnings.ts")

describe("resolveAffiliateCommissionBaseCents", () => {
  it("monthly with no tax — uses total_excluding_tax", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 2399,
      total_excluding_tax: 2399,
      amount_paid: 2399,
    })
    assert.equal(result.source, "total_excluding_tax")
    assert.equal(result.basisCents, 2399)
    assert.equal(centsToMajorUnits(result.basisCents), 23.99)
    assert.equal(calculateAffiliateCommission(23.99), 4.32)
  })

  it("monthly with exclusive tax — excludes tax from base", () => {
    // $23.99 + $2.00 tax; amount_paid includes tax
    const result = resolveAffiliateCommissionBaseCents({
      total: 2599,
      total_excluding_tax: 2399,
      amount_paid: 2599,
      total_taxes: [{ amount: 200 }],
    })
    assert.equal(result.source, "total_excluding_tax")
    assert.equal(result.basisCents, 2399)
    assert.equal(calculateAffiliateCommission(23.99), 4.32)
    // amount_paid must never be used as base
    assert.notEqual(result.basisCents, 2599)
  })

  it("yearly subscription — uses invoice total_excluding_tax only", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 24470,
      total_excluding_tax: 24470,
    })
    assert.equal(result.basisCents, 24470)
    assert.equal(centsToMajorUnits(result.basisCents), 244.7)
    assert.equal(calculateAffiliateCommission(244.7), 44.05)
  })

  it("6-month subscription", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 13674,
      total_excluding_tax: 13674,
    })
    assert.equal(result.basisCents, 13674)
    assert.equal(calculateAffiliateCommission(136.74), 24.61)
  })

  it("discounted / coupon — base reflects discounted revenue", () => {
    // List 23.99, 50% off → 12.00 (1200 cents) excl tax
    const result = resolveAffiliateCommissionBaseCents({
      total: 1200,
      total_excluding_tax: 1200,
      amount_paid: 1200,
    })
    assert.equal(result.basisCents, 1200)
    assert.equal(calculateAffiliateCommission(12), 2.16)
  })

  it("coupon + tax — discounts in, tax out", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 1300,
      total_excluding_tax: 1200,
      amount_paid: 1300,
      total_taxes: [{ amount: 100 }],
    })
    assert.equal(result.basisCents, 1200)
    assert.equal(calculateAffiliateCommission(12), 2.16)
  })

  it("free trial $0 invoice — zero base", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 0,
      total_excluding_tax: 0,
      amount_paid: 0,
    })
    assert.equal(result.basisCents, 0)
    assert.equal(calculateAffiliateCommission(0), 0)
  })

  it("proration invoice — uses Stripe totals as-is", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 1575,
      total_excluding_tax: 1450,
      total_taxes: [{ amount: 125 }],
      amount_paid: 1575,
    })
    assert.equal(result.source, "total_excluding_tax")
    assert.equal(result.basisCents, 1450)
  })

  it("fallback: total minus tax when total_excluding_tax is null", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 2599,
      total_excluding_tax: null,
      total_taxes: [{ amount: 200 }],
      amount_paid: 2599,
    })
    assert.equal(result.source, "total_minus_tax")
    assert.equal(result.basisCents, 2399)
  })

  it("fallback: total when no tax and total_excluding_tax null", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 2399,
      total_excluding_tax: null,
      total_taxes: [],
      amount_paid: 2399,
    })
    assert.equal(result.source, "total")
    assert.equal(result.basisCents, 2399)
  })

  it("never prefers amount_paid over tax-excluded fields", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 3000,
      total_excluding_tax: 2399,
      amount_paid: 99999,
    })
    assert.equal(result.basisCents, 2399)
  })
})

describe("calculateAffiliateCommission", () => {
  it("uses 18% rate", () => {
    assert.equal(COMMISSION_RATE, 0.18)
    assert.equal(calculateAffiliateCommission(100), 18)
  })
})

describe("extractStripePriceIdFromInvoice", () => {
  it("reads pricing.price_details.price string", () => {
    const id = extractStripePriceIdFromInvoice({
      lines: {
        data: [
          {
            pricing: { price_details: { price: "price_monthly" } },
            parent: { type: "subscription_item_details" },
          },
        ],
      },
    })
    assert.equal(id, "price_monthly")
  })

  it("prefers subscription line over invoice item", () => {
    const id = extractStripePriceIdFromInvoice({
      lines: {
        data: [
          {
            pricing: { price_details: { price: "price_addon" } },
            parent: { type: "invoice_item_details" },
          },
          {
            pricing: { price_details: { price: "price_yearly" } },
            parent: { type: "subscription_item_details" },
          },
        ],
      },
    })
    assert.equal(id, "price_yearly")
  })

  it("supports legacy price.id shape", () => {
    const id = extractStripePriceIdFromInvoice({
      lines: {
        data: [{ price: { id: "price_legacy" }, type: "subscription" }],
      },
    })
    assert.equal(id, "price_legacy")
  })
})
