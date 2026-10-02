import type { EffectiveMonetizationFlags } from "./monetizationConfig.ts"

export type MonetizationPlatform = "web" | "ios"

/** Free-plan caps and Pro-feature gating apply only when enforcement is on. */
export function entitlementGatingActive(
  flags: EffectiveMonetizationFlags | null | undefined
): boolean {
  return flags?.entitlementEnforcementEnabled === true
}

export function platformPaywallEnabled(
  platform: MonetizationPlatform,
  flags: EffectiveMonetizationFlags | null | undefined
): boolean {
  if (!flags) return false
  return platform === "web"
    ? flags.webPaywallEnabled === true
    : flags.iosPaywallEnabled === true
}

/**
 * Show the shared TradeTraxs Pro upgrade sheet (StoreKit / Stripe).
 * Requires enforcement + platform paywall — never when monetization is paused.
 */
export function canPresentProPaywall(
  platform: MonetizationPlatform,
  flags: EffectiveMonetizationFlags | null | undefined
): boolean {
  return entitlementGatingActive(flags) && platformPaywallEnabled(platform, flags)
}

/** Block Pro-only surfaces in UI when enforcement is on and user is not Pro. */
export function shouldGateProFeature(
  isPro: boolean,
  flags: EffectiveMonetizationFlags | null | undefined
): boolean {
  if (isPro) return false
  return entitlementGatingActive(flags)
}

/** Client-side Free limit preflight (server remains authoritative). */
export function shouldEnforceFreeLimits(
  flags: EffectiveMonetizationFlags | null | undefined
): boolean {
  return entitlementGatingActive(flags)
}
