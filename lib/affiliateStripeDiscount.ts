/**
 * Affiliate first-invoice discount (10% once) + durable attribution metadata.
 * Commission attribution must NOT depend on coupon presence on renewals.
 */

import type Stripe from "stripe"

/** Shared Stripe coupon for all affiliate promotion codes. */
export const AFFILIATE_ONCE_COUPON_NAME = "TradeTraxs Affiliate 10% Once"

export const AFFILIATE_ONCE_COUPON_METADATA = {
  tradetraxs_purpose: "affiliate_first_invoice_discount",
  percent_off: "10",
  duration: "once",
} as const

export const AFFILIATE_DISCOUNT_PERCENT_OFF = 10

/** Stripe metadata keys for durable affiliate attribution (session / subscription / customer). */
export const AFFILIATE_META = {
  affiliateUserId: "affiliate_user_id",
  affiliateCode: "affiliate_code",
  referredUserId: "referred_user_id",
} as const

export type AffiliateAttributionMeta = {
  affiliateUserId: string
  affiliateCode: string
  referredUserId: string
}

export type AffiliateCheckoutRow = {
  user_id: string
  code: string
  stripe_promo_code_id: string | null
}

export function normalizeAffiliateCode(raw: string | null | undefined): string {
  if (raw == null) return ""
  return String(raw).trim().toUpperCase()
}

export function buildAffiliateAttributionMetadata(
  input: AffiliateAttributionMeta
): Record<string, string> {
  return {
    [AFFILIATE_META.affiliateUserId]: input.affiliateUserId,
    [AFFILIATE_META.affiliateCode]: normalizeAffiliateCode(input.affiliateCode),
    [AFFILIATE_META.referredUserId]: input.referredUserId,
  }
}

export function readAffiliateCodeFromStripeMetadata(
  metadata: Stripe.Metadata | null | undefined
): string {
  if (!metadata) return ""
  return normalizeAffiliateCode(metadata[AFFILIATE_META.affiliateCode])
}

export function readAffiliateUserIdFromStripeMetadata(
  metadata: Stripe.Metadata | null | undefined
): string {
  if (!metadata) return ""
  const raw = metadata[AFFILIATE_META.affiliateUserId]
  return raw != null ? String(raw).trim() : ""
}

/**
 * Prefer durable DB attribution (`profiles.referred_by`), then Stripe metadata.
 * Never uses invoice discount / promotion_code as the primary renewal source.
 */
export function resolveAffiliateCodeForCommission(input: {
  profileReferredBy?: string | null
  subscriptionMetadata?: Stripe.Metadata | null
  customerMetadata?: Stripe.Metadata | null
  checkoutSessionMetadata?: Stripe.Metadata | null
}): string {
  const fromProfile = normalizeAffiliateCode(input.profileReferredBy)
  if (fromProfile) return fromProfile

  const fromSub = readAffiliateCodeFromStripeMetadata(input.subscriptionMetadata)
  if (fromSub) return fromSub

  const fromCustomer = readAffiliateCodeFromStripeMetadata(input.customerMetadata)
  if (fromCustomer) return fromCustomer

  const fromSession = readAffiliateCodeFromStripeMetadata(
    input.checkoutSessionMetadata
  )
  if (fromSession) return fromSession

  return ""
}

/**
 * Whether an invoice should be eligible for affiliate commission ledger insert.
 * invoice.paid already implies success; still gate void/draft/open and $0.
 */
export function shouldRecordAffiliateCommission(input: {
  invoiceStatus?: string | null
  commissionBaseMajor: number
}): boolean {
  const status = String(input.invoiceStatus ?? "").toLowerCase()
  if (status && status !== "paid") return false
  if (!Number.isFinite(input.commissionBaseMajor)) return false
  return input.commissionBaseMajor > 0
}

/** Expected first-paid amount after 10% once discount (for tests / docs — not used in live commission math). */
export function applyAffiliateOncePercentOff(
  preTaxListCents: number,
  percentOff: number = AFFILIATE_DISCOUNT_PERCENT_OFF
): number {
  const list = Math.max(0, Math.round(preTaxListCents))
  const pct = Math.min(100, Math.max(0, percentOff))
  return Math.max(0, Math.round(list * (1 - pct / 100)))
}

export async function findAffiliateOnceCouponId(
  stripe: Stripe
): Promise<string | null> {
  const envId = process.env.STRIPE_AFFILIATE_ONCE_COUPON_ID?.trim()
  if (envId) {
    try {
      const coupon = await stripe.coupons.retrieve(envId)
      if (coupon.valid && coupon.duration === "once" && Number(coupon.percent_off) === 10) {
        return coupon.id
      }
    } catch {
      /* fall through to search / create */
    }
  }

  const listed = await stripe.coupons.list({ limit: 100 })
  for (const coupon of listed.data) {
    if (!coupon.valid) continue
    if (coupon.duration !== "once") continue
    if (Number(coupon.percent_off) !== 10) continue
    if (
      coupon.metadata?.tradetraxs_purpose ===
        AFFILIATE_ONCE_COUPON_METADATA.tradetraxs_purpose ||
      coupon.name === AFFILIATE_ONCE_COUPON_NAME
    ) {
      return coupon.id
    }
  }

  return null
}

export async function ensureAffiliateOnceCoupon(
  stripe: Stripe
): Promise<Stripe.Coupon> {
  const existingId = await findAffiliateOnceCouponId(stripe)
  if (existingId) {
    return stripe.coupons.retrieve(existingId)
  }

  return stripe.coupons.create({
    percent_off: AFFILIATE_DISCOUNT_PERCENT_OFF,
    duration: "once",
    name: AFFILIATE_ONCE_COUPON_NAME,
    metadata: { ...AFFILIATE_ONCE_COUPON_METADATA },
  })
}

export async function createAffiliatePromotionCode(params: {
  stripe: Stripe
  code: string
  affiliateUserId: string
  couponId?: string
}): Promise<Stripe.PromotionCode> {
  const code = normalizeAffiliateCode(params.code)
  if (!code) {
    throw new Error("Affiliate promotion code is required")
  }

  const couponId =
    params.couponId ?? (await ensureAffiliateOnceCoupon(params.stripe)).id

  return params.stripe.promotionCodes.create({
    promotion: {
      type: "coupon",
      coupon: couponId,
    },
    code,
    active: true,
    metadata: {
      affiliate_user_id: params.affiliateUserId,
      affiliate_code: code,
      tradetraxs_purpose: AFFILIATE_ONCE_COUPON_METADATA.tradetraxs_purpose,
    },
  })
}

/**
 * Deactivate an old promo (e.g. forever coupon) and create a replacement on the once coupon
 * using the same customer-facing code when possible.
 */
export async function replaceAffiliatePromotionCodeWithOnce(params: {
  stripe: Stripe
  code: string
  affiliateUserId: string
  existingPromoId?: string | null
}): Promise<{ promotionCode: Stripe.PromotionCode; deactivatedOld: boolean }> {
  const code = normalizeAffiliateCode(params.code)
  let deactivatedOld = false

  if (params.existingPromoId?.trim()) {
    try {
      await params.stripe.promotionCodes.update(params.existingPromoId.trim(), {
        active: false,
      })
      deactivatedOld = true
    } catch {
      /* may already be inactive / missing */
    }
  }

  // If another active promo still holds this code, deactivate it too.
  const existing = await params.stripe.promotionCodes.list({
    code,
    active: true,
    limit: 10,
  })
  for (const promo of existing.data) {
    await params.stripe.promotionCodes.update(promo.id, { active: false })
    deactivatedOld = true
  }

  const promotionCode = await createAffiliatePromotionCode({
    stripe: params.stripe,
    code,
    affiliateUserId: params.affiliateUserId,
  })

  return { promotionCode, deactivatedOld }
}
