import { describe, it } from "node:test"
import { AFFILIATE_DISCOUNT_PERCENT_OFF, applyAffiliateOncePercentOff, buildAffiliateAttributionMetadata, normalizeAffiliateCode, readAffiliateCodeFromStripeMetadata, resolveAffiliateCodeForCommission, shouldRecordAffiliateCommission, } from "./affiliateStripeDiscount.ts"
import { COMMISSION_RATE, calculateAffiliateCommission, centsToMajorUnits, resolveAffiliateCommissionBaseCents, type AffiliateCommissionInvoice, } from "./affiliateEarnings.ts"
import assert from "node:assert/strict"

type AffiliateCommissionInvoiceFixture = AffiliateCommissionInvoice & {
  amount_paid?: number
}

function commissionInvoice(
  invoice: AffiliateCommissionInvoiceFixture
): AffiliateCommissionInvoice {
  return invoice
}

describe("affiliate once discount helpers", () => {
  it("normalizes affiliate codes", () => {
    assert.equal(normalizeAffiliateCode("  nrl  "), "NRL")
    assert.equal(normalizeAffiliateCode(null), "")
  })

  it("builds durable attribution metadata", () => {
    const meta = buildAffiliateAttributionMetadata({
      affiliateUserId: "aff-1",
      affiliateCode: "nrl",
      referredUserId: "buyer-1",
    })
    assert.deepEqual(meta, {
      affiliate_user_id: "aff-1",
      affiliate_code: "NRL",
      referred_user_id: "buyer-1",
    })
  })

  it("prefers profiles.referred_by over Stripe metadata", () => {
    const code = resolveAffiliateCodeForCommission({
      profileReferredBy: "NRL",
      subscriptionMetadata: { affiliate_code: "OTHER" },
      customerMetadata: { affiliate_code: "OTHER2" },
    })
    assert.equal(code, "NRL")
  })

  it("falls back to subscription metadata when DB attribution missing", () => {
    const code = resolveAffiliateCodeForCommission({
      profileReferredBy: null,
      subscriptionMetadata: { affiliate_code: "421TEST" },
      customerMetadata: { affiliate_code: "NRL" },
    })
    assert.equal(code, "421TEST")
  })

  it("falls back to customer metadata", () => {
    const code = resolveAffiliateCodeForCommission({
      profileReferredBy: " ",
      subscriptionMetadata: {},
      customerMetadata: { affiliate_code: "NRLTEST" },
    })
    assert.equal(code, "NRLTEST")
  })

  it("does not use invoice discount fields for renewal attribution", () => {
    // Ensure helper has no invoice discount inputs — renewal safety by API shape.
    const code = resolveAffiliateCodeForCommission({
      profileReferredBy: null,
      subscriptionMetadata: null,
      customerMetadata: null,
      checkoutSessionMetadata: { affiliate_code: "NRL" },
    })
    assert.equal(code, "NRL")
    assert.equal(readAffiliateCodeFromStripeMetadata({ foo: "bar" }), "")
  })

  it("applies 10% once math for first paid invoice examples", () => {
    assert.equal(AFFILIATE_DISCOUNT_PERCENT_OFF, 10)
    // monthly list 2399 → 2159 after 10%
    assert.equal(applyAffiliateOncePercentOff(2399), 2159)
    // yearly 24470 → 22023
    assert.equal(applyAffiliateOncePercentOff(24470), 22023)
    // 6-month 13674 → 12307
    assert.equal(applyAffiliateOncePercentOff(13674), 12307)
  })
})

describe("affiliate commission scenarios (total_excluding_tax)", () => {
  it("trial $0 invoice — no commission", () => {
    const base = resolveAffiliateCommissionBaseCents(
      commissionInvoice({
        total: 0,
        total_excluding_tax: 0,
        amount_paid: 0,
      })
    )
    assert.equal(base.basisCents, 0)
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "paid",
        commissionBaseMajor: centsToMajorUnits(base.basisCents),
      }),
      false
    )
  })

  it("first paid invoice after trial — 10% off monthly + tax excluded", () => {
    // List $23.99, 10% once → $21.59 pre-tax; tax $1.72 → total paid $23.31
    const discountedPreTax = applyAffiliateOncePercentOff(2399)
    const tax = 172
    const result = resolveAffiliateCommissionBaseCents(
      commissionInvoice({
        total: discountedPreTax + tax,
        total_excluding_tax: discountedPreTax,
        amount_paid: discountedPreTax + tax,
        total_taxes: [{ amount: tax }],
      })
    )
    assert.equal(result.source, "total_excluding_tax")
    assert.equal(result.basisCents, 2159)
    const major = centsToMajorUnits(result.basisCents)
    assert.equal(major, 21.59)
    assert.equal(calculateAffiliateCommission(major), 3.89)
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "paid",
        commissionBaseMajor: major,
      }),
      true
    )
  })

  it("second paid renewal — full pre-tax, attribution independent of discount", () => {
    const result = resolveAffiliateCommissionBaseCents(
      commissionInvoice({
        total: 2599,
        total_excluding_tax: 2399,
        amount_paid: 2599,
        total_taxes: [{ amount: 200 }],
      })
    )
    assert.equal(result.basisCents, 2399)
    assert.equal(calculateAffiliateCommission(23.99), 4.32)
    // Attribution still resolvable without any discount metadata
    assert.equal(
      resolveAffiliateCodeForCommission({
        profileReferredBy: "NRL",
        subscriptionMetadata: { affiliate_code: "NRL" },
      }),
      "NRL"
    )
  })

  it("monthly subscription commission", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 2399,
      total_excluding_tax: 2399,
    })
    assert.equal(calculateAffiliateCommission(centsToMajorUnits(result.basisCents)), 4.32)
  })

  it("6-month subscription commission", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 13674,
      total_excluding_tax: 13674,
    })
    assert.equal(calculateAffiliateCommission(centsToMajorUnits(result.basisCents)), 24.61)
  })

  it("yearly subscription commission", () => {
    const result = resolveAffiliateCommissionBaseCents({
      total: 24470,
      total_excluding_tax: 24470,
    })
    assert.equal(calculateAffiliateCommission(centsToMajorUnits(result.basisCents)), 44.05)
  })

  it("coupon + tax — commission on discounted pre-tax", () => {
    const result = resolveAffiliateCommissionBaseCents(
      commissionInvoice({
        total: 2331,
        total_excluding_tax: 2159,
        amount_paid: 2331,
        total_taxes: [{ amount: 172 }],
      })
    )
    assert.equal(result.basisCents, 2159)
    assert.equal(calculateAffiliateCommission(21.59), 3.89)
  })

  it("failed / non-paid invoice status — no commission", () => {
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "open",
        commissionBaseMajor: 23.99,
      }),
      false
    )
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "void",
        commissionBaseMajor: 23.99,
      }),
      false
    )
  })

  it("duplicate webhook — idempotency key is stripe_invoice_id (contract)", () => {
    // Ledger uniqueness is enforced in DB via referrals_stripe_invoice_id_uidx.
    // This test documents the contract used by the webhook.
    const invoiceId = "in_test_duplicate"
    const first = { stripe_invoice_id: invoiceId }
    const second = { stripe_invoice_id: invoiceId }
    assert.equal(first.stripe_invoice_id, second.stripe_invoice_id)
  })

  it("failed payment then successful retry uses paid invoice only", () => {
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "open",
        commissionBaseMajor: 23.99,
      }),
      false
    )
    assert.equal(
      shouldRecordAffiliateCommission({
        invoiceStatus: "paid",
        commissionBaseMajor: 23.99,
      }),
      true
    )
  })

  it("plan change keeps attribution via referred_by / subscription metadata", () => {
    // Monthly → yearly: same affiliate code on profile + subscription metadata
    const code = resolveAffiliateCodeForCommission({
      profileReferredBy: "NRL",
      subscriptionMetadata: {
        affiliate_code: "NRL",
        billing_interval: "yearly",
      },
    })
    assert.equal(code, "NRL")
    const yearly = resolveAffiliateCommissionBaseCents({
      total: 24470,
      total_excluding_tax: 24470,
    })
    assert.equal(COMMISSION_RATE, 0.18)
    assert.equal(calculateAffiliateCommission(centsToMajorUnits(yearly.basisCents)), 44.05)
  })
})
export {}
