/**
 * Affiliate “display total earnings” (dashboard, payout balance RPC):
 * `referral_count × per-referral amount` — not Stripe settlement timing.
 */
export const AFFILIATE_PER_REFERRAL_EARNINGS = 2.88

export function affiliateTotalEarningsFromReferralCount(referralCount: number): number {
  const n = Number.isFinite(referralCount) ? Math.max(0, Math.floor(referralCount)) : 0
  return Math.round(n * AFFILIATE_PER_REFERRAL_EARNINGS * 100) / 100
}
