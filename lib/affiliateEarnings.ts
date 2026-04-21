/**
 * Affiliate “display total earnings” (dashboard, payout balance RPC):
 * `referral_count × per-referral amount` — not Stripe settlement timing.
 */
export const COMMISSION_RATE = 0.18
export const SUBSCRIPTION_PRICE = 23.99
export const AFFILIATE_PER_REFERRAL_EARNINGS =
  Math.round(SUBSCRIPTION_PRICE * COMMISSION_RATE * 100) / 100

export function affiliateTotalEarningsFromReferralCount(referralCount: number): number {
  const n = Number.isFinite(referralCount) ? Math.max(0, Math.floor(referralCount)) : 0
  return Math.round(n * AFFILIATE_PER_REFERRAL_EARNINGS * 100) / 100
}
