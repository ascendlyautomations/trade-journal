/** Matches affiliate dashboard / settings affiliate tab (Pro plan commission model). */
export const AFFILIATE_PLAN_PRICE = 15.99
export const AFFILIATE_COMMISSION_RATE = 0.18

export function estimateEarningsFromReferralCount(referralCount: number): number {
  const n = Number.isFinite(referralCount) ? Math.max(0, Math.floor(referralCount)) : 0
  return n * AFFILIATE_PLAN_PRICE * AFFILIATE_COMMISSION_RATE
}

/**
 * Balance basis for payout caps: prefer Stripe-tracked `referral_earnings` when &gt; 0,
 * otherwise the same estimate used on the affiliate dashboard.
 */
export function payoutEarningsBase(recordedReferralEarnings: number | null | undefined, referralCount: number): number {
  const recorded = recordedReferralEarnings != null && Number.isFinite(Number(recordedReferralEarnings))
    ? Math.max(0, Number(recordedReferralEarnings))
    : 0
  const estimated = estimateEarningsFromReferralCount(referralCount)
  return recorded > 0 ? recorded : estimated
}
