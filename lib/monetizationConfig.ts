/**
 * Server-controlled iOS monetization flags.
 *
 * Production defaults are both false. A missing or unreadable config must stay
 * false so a failed fetch cannot turn purchases or Free-plan limits on.
 *
 * `IOS_PAID_SUBSCRIPTIONS_ENABLED` is not a second switch. The database row is
 * the authority.
 *
 * Launch access for people who joined before monetization is also server-side
 * and defaults to off (`launch_access_mode = none`). Set
 * `created_before_cutoff` plus `launch_access_cutoff_at` later if you choose
 * to grandfather. This file does not pick that cutoff.
 */

export type LaunchAccessMode = "none" | "created_before_cutoff"

export type MonetizationGlobalSettings = {
  iosPaywallEnabled: boolean
  entitlementEnforcementEnabled: boolean
  launchAccessMode: LaunchAccessMode
  launchAccessCutoffAt: string | null
}

export type MonetizationAccountOverride = {
  iosPaywallEnabled: boolean | null
  entitlementEnforcementEnabled: boolean | null
}

export type EffectiveMonetizationFlags = {
  iosPaywallEnabled: boolean
  entitlementEnforcementEnabled: boolean
}

export const MONETIZATION_FLAGS_FAIL_CLOSED: EffectiveMonetizationFlags = {
  iosPaywallEnabled: false,
  entitlementEnforcementEnabled: false,
}

export const LAUNCH_ACCESS_DISABLED: Pick<
  MonetizationGlobalSettings,
  "launchAccessMode" | "launchAccessCutoffAt"
> = {
  launchAccessMode: "none",
  launchAccessCutoffAt: null,
}

export function resolveEffectiveMonetizationFlags(
  globalSettings: MonetizationGlobalSettings | null | undefined,
  accountOverride: MonetizationAccountOverride | null | undefined
): EffectiveMonetizationFlags {
  if (!globalSettings) return { ...MONETIZATION_FLAGS_FAIL_CLOSED }
  return {
    iosPaywallEnabled:
      accountOverride?.iosPaywallEnabled ?? globalSettings.iosPaywallEnabled,
    entitlementEnforcementEnabled:
      accountOverride?.entitlementEnforcementEnabled ??
      globalSettings.entitlementEnforcementEnabled,
  }
}

export function parseLaunchAccessMode(value: unknown): LaunchAccessMode {
  return value === "created_before_cutoff" ? "created_before_cutoff" : "none"
}

/**
 * True only when the stored policy is explicitly `created_before_cutoff`
 * and the profile was created before that timestamp. Default policy is off.
 */
export function launchAccessGrantApplies(
  profileCreatedAt: string | null | undefined,
  policy: {
    launchAccessMode?: LaunchAccessMode | null
    launchAccessCutoffAt?: string | null
  } | null | undefined
): boolean {
  if (policy?.launchAccessMode !== "created_before_cutoff") return false
  const cutoffRaw = policy.launchAccessCutoffAt
  if (!cutoffRaw || !profileCreatedAt) return false
  const cutoff = new Date(cutoffRaw)
  const created = new Date(profileCreatedAt)
  if (Number.isNaN(cutoff.getTime()) || Number.isNaN(created.getTime())) {
    return false
  }
  return created.getTime() < cutoff.getTime()
}

/** Absent token is not a mismatch. A present token must match the signed-in user. */
export function appleAppAccountTokenMatchesUser(
  appAccountToken: string | null | undefined,
  userId: string
): boolean {
  const token = appAccountToken?.trim()
  if (!token) return true
  return token.toLowerCase() === userId.trim().toLowerCase()
}

/**
 * Whether the web app should still offer Stripe checkout.
 * An authoritative server entitlement of Pro suppresses checkout.
 * A failed entitlement fetch falls back to the existing profile gate.
 */
export function shouldOfferStripeCheckout(input: {
  profileNeedsCheckout: boolean
  serverTraxProActive: boolean | null
}): boolean {
  if (input.serverTraxProActive === true) return false
  return input.profileNeedsCheckout
}
