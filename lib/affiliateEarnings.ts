/**
 * Affiliate commission display helpers.
 * Recorded earnings come from profiles.referral_earnings (webhook-maintained)
 * and/or public.referrals.amount_earned — not referral_count × fixed price.
 */
export const COMMISSION_RATE = 0.18

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
