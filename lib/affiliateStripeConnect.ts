import type Stripe from "stripe"

/** Columns returned for affiliate-facing Connect UI (matches `affiliates` migration). */
export const AFFILIATE_CONNECT_SELECT = [
  "id",
  "code",
  "stripe_connected_account_id",
  "stripe_onboarding_complete",
  "stripe_details_submitted",
  "stripe_charges_enabled",
  "stripe_payouts_enabled",
  "stripe_onboarding_last_url",
  "stripe_onboarding_updated_at",
].join(", ")

export type AffiliateConnectRow = {
  id: string
  code: string | null
  stripe_connected_account_id: string | null
  stripe_onboarding_complete: boolean
  stripe_details_submitted: boolean
  stripe_charges_enabled: boolean
  stripe_payouts_enabled: boolean
  stripe_onboarding_last_url: string | null
  stripe_onboarding_updated_at: string | null
}

export function parseAffiliateConnectRow(raw: Record<string, unknown>): AffiliateConnectRow {
  return {
    id: String(raw.id ?? ""),
    code: raw.code != null ? String(raw.code) : null,
    stripe_connected_account_id:
      raw.stripe_connected_account_id != null ? String(raw.stripe_connected_account_id) : null,
    stripe_onboarding_complete: Boolean(raw.stripe_onboarding_complete),
    stripe_details_submitted: Boolean(raw.stripe_details_submitted),
    stripe_charges_enabled: Boolean(raw.stripe_charges_enabled),
    stripe_payouts_enabled: Boolean(raw.stripe_payouts_enabled),
    stripe_onboarding_last_url:
      raw.stripe_onboarding_last_url != null ? String(raw.stripe_onboarding_last_url) : null,
    stripe_onboarding_updated_at:
      raw.stripe_onboarding_updated_at != null ? String(raw.stripe_onboarding_updated_at) : null,
  }
}

/** Ready for payout requests: onboarded enough that Stripe allows payouts. */
export function isAffiliatePayoutSetupComplete(row: AffiliateConnectRow | null): boolean {
  return Boolean(row?.stripe_onboarding_complete)
}

export type ConnectUiPhase = "not_started" | "in_progress" | "complete"

export function affiliateConnectPhase(row: AffiliateConnectRow | null): ConnectUiPhase {
  if (!row?.stripe_connected_account_id) return "not_started"
  if (row.stripe_onboarding_complete) return "complete"
  return "in_progress"
}

export function affiliateConnectPhaseLabel(phase: ConnectUiPhase): string {
  switch (phase) {
    case "not_started":
      return "Not started"
    case "in_progress":
      return "Setup in progress"
    case "complete":
      return "Setup complete"
    default:
      return "—"
  }
}

export function stripeAccountToAffiliateConnectPatch(account: Stripe.Account): {
  stripe_details_submitted: boolean
  stripe_charges_enabled: boolean
  stripe_payouts_enabled: boolean
  stripe_onboarding_complete: boolean
  stripe_onboarding_updated_at: string
} {
  const detailsSubmitted = Boolean(account.details_submitted)
  const chargesEnabled = Boolean(account.charges_enabled)
  const payoutsEnabled = Boolean(account.payouts_enabled)
  const onboardingComplete = Boolean(detailsSubmitted && payoutsEnabled)

  return {
    stripe_details_submitted: detailsSubmitted,
    stripe_charges_enabled: chargesEnabled,
    stripe_payouts_enabled: payoutsEnabled,
    stripe_onboarding_complete: onboardingComplete,
    stripe_onboarding_updated_at: new Date().toISOString(),
  }
}
