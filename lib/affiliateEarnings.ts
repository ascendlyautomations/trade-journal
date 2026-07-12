/**
 * Affiliate commission helpers.
 * Earnings are recorded from Stripe invoice revenue (after discounts, before tax)
 * × COMMISSION_RATE — never from hardcoded plan prices or amount_paid (may include tax).
 */

export const COMMISSION_RATE = 0.18

/** Minimal invoice shape needed for commission base (Stripe.Invoice-compatible). */
export type AffiliateCommissionInvoice = {
  total?: number | null
  total_excluding_tax?: number | null
  /** Legacy exclusive-tax total (older API payloads). */
  tax?: number | null
  total_taxes?: Array<{ amount?: number | null }> | null
  /** Legacy tax amount list (older API payloads). */
  total_tax_amounts?: Array<{ amount?: number | null }> | null
  lines?: {
    data?: Array<{
      amount?: number | null
      pricing?: {
        price_details?: {
          price?: string | { id?: string | null } | null
        } | null
      } | null
      /** Legacy line shape (pre pricing.price_details). */
      price?: string | { id?: string | null } | null
      parent?: {
        type?: string | null
        subscription_item_details?: unknown
      } | null
      type?: string | null
    }> | null
  } | null
}

export type CommissionBaseResult = {
  /** Commission base in cents (after discounts, before tax). */
  basisCents: number
  /** Which Stripe-derived path produced the base. */
  source:
    | "total_excluding_tax"
    | "total_minus_tax"
    | "total"
    | "zero"
}

function sumTaxCents(invoice: AffiliateCommissionInvoice): number {
  const fromTotalTaxes = (invoice.total_taxes ?? []).reduce((sum, row) => {
    const n = Number(row?.amount ?? 0)
    return sum + (Number.isFinite(n) ? n : 0)
  }, 0)
  if (fromTotalTaxes > 0) return fromTotalTaxes

  const fromLegacy = (invoice.total_tax_amounts ?? []).reduce((sum, row) => {
    const n = Number(row?.amount ?? 0)
    return sum + (Number.isFinite(n) ? n : 0)
  }, 0)
  if (fromLegacy > 0) return fromLegacy

  const legacyTax = Number(invoice.tax ?? 0)
  return Number.isFinite(legacyTax) && legacyTax > 0 ? legacyTax : 0
}

/**
 * Subscription revenue after discounts and before taxes (cents).
 * Never uses amount_paid (can include tax).
 */
export function resolveAffiliateCommissionBaseCents(
  invoice: AffiliateCommissionInvoice
): CommissionBaseResult {
  const excludingTax = invoice.total_excluding_tax
  if (excludingTax != null && Number.isFinite(Number(excludingTax))) {
    return {
      basisCents: Math.max(0, Math.round(Number(excludingTax))),
      source: "total_excluding_tax",
    }
  }

  const totalCents = Math.max(0, Math.round(Number(invoice.total ?? 0)))
  const taxCents = sumTaxCents(invoice)

  if (taxCents > 0) {
    return {
      basisCents: Math.max(0, totalCents - taxCents),
      source: "total_minus_tax",
    }
  }

  if (totalCents > 0) {
    return { basisCents: totalCents, source: "total" }
  }

  return { basisCents: 0, source: "zero" }
}

/** Convert cents → major currency units (2 dp). */
export function centsToMajorUnits(cents: number): number {
  return Math.round((Math.max(0, cents) / 100) * 100) / 100
}

/** commission = round(baseMajor * rate, 2) */
export function calculateAffiliateCommission(
  commissionBaseMajor: number,
  rate: number = COMMISSION_RATE
): number {
  const base = Number(commissionBaseMajor)
  if (!Number.isFinite(base) || base <= 0) return 0
  const r = Number(rate)
  if (!Number.isFinite(r) || r <= 0) return 0
  return Math.round(base * r * 100) / 100
}

function priceIdFromLine(
  line: NonNullable<NonNullable<AffiliateCommissionInvoice["lines"]>["data"]>[number]
): string | null {
  const fromPricing = line.pricing?.price_details?.price
  if (typeof fromPricing === "string" && fromPricing.trim()) {
    return fromPricing.trim()
  }
  if (
    fromPricing &&
    typeof fromPricing === "object" &&
    typeof fromPricing.id === "string" &&
    fromPricing.id.trim()
  ) {
    return fromPricing.id.trim()
  }

  const legacy = line.price
  if (typeof legacy === "string" && legacy.trim()) return legacy.trim()
  if (
    legacy &&
    typeof legacy === "object" &&
    typeof legacy.id === "string" &&
    legacy.id.trim()
  ) {
    return legacy.id.trim()
  }
  return null
}

/**
 * First subscription-related Price ID on the invoice (analytics only — not for commission math).
 */
export function extractStripePriceIdFromInvoice(
  invoice: AffiliateCommissionInvoice
): string | null {
  const lines = invoice.lines?.data ?? []
  if (!lines.length) return null

  const ranked = [...lines].sort((a, b) => {
    const score = (line: (typeof lines)[number]) => {
      if (line.parent?.type === "subscription_item_details") return 0
      if (line.type === "subscription") return 0
      return 1
    }
    return score(a) - score(b)
  })

  for (const line of ranked) {
    const id = priceIdFromLine(line)
    if (id) return id
  }
  return null
}

export function recordedAffiliateEarnings(value: unknown): number {
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0) return 0
  return Math.round(n * 100) / 100
}

export function sumReferralsLedgerAmounts(
  rows: Array<{ amount_earned?: unknown }> | null | undefined
): number {
  let sum = 0
  for (const row of rows ?? []) {
    const n = Number(row.amount_earned)
    if (Number.isFinite(n)) sum += n
  }
  return Math.round(sum * 100) / 100
}

/** Prefer webhook cumulative on profile; fall back to summing ledger rows. */
export function resolveRecordedAffiliateEarnings(
  profileReferralEarnings: unknown,
  ledgerRows?: Array<{ amount_earned?: unknown }> | null
): number {
  const fromProfile = recordedAffiliateEarnings(profileReferralEarnings)
  if (fromProfile > 0) return fromProfile
  return sumReferralsLedgerAmounts(ledgerRows)
}
