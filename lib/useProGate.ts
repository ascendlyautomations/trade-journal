"use client"

import { useCallback } from "react"
import { useProUpgradeOptional } from "@/app/components/monetization/ProUpgradeProvider"
import { useBillingEntitlementOptional } from "@/app/components/monetization/BillingEntitlementProvider"
import { resolveClientProAccess, type BillingProvider, type ClientProAccess, type BillingEntitlementSnapshot, type BillingEntitlementStatus } from "./billingEntitlement"
import { isProActive } from "./subscription"
import type { ProFeatureKind, ProGateReason, ProLimitKind } from "./proGateReason"
import { parseProLimitPayload } from "./proGateReason"
import { entitlementGatingActive, shouldEnforceFreeLimits } from "./proMonetizationPolicy"
import type { ProUpgradeRetryAction } from "./proUpgradeContinuation"

type ProfileLike = Parameters<typeof isProActive>[0]

export function useProGate(profile: ProfileLike) {
  const upgrade = useProUpgradeOptional()
  const billing = useBillingEntitlementOptional()
  const profileIsPro = isProActive(profile)
  const flags = upgrade?.flags
  const enforcementOn = entitlementGatingActive(flags)
  const access: ClientProAccess = billing
    ? billing.access
    : resolveClientProAccess({
        signedIn: false,
        profileIsPro,
        status: "ready",
        traxProActive: profileIsPro,
      })
  const isPro = access === "pro"
  const proFeatureUnlocked = access === "pro" || !enforcementOn
  const showProLocks = access === "free" && enforcementOn

  const shouldGateFeature = useCallback(
    (featureIsProOnly = true) => {
      if (!featureIsProOnly || access === "pro") return false
      if (access === "unknown") return false
      return upgrade?.shouldGateProFeature(false) ?? false
    },
    [access, upgrade]
  )

  const presentLimit = useCallback(
    (limit: ProLimitKind, retry?: ProUpgradeRetryAction) => {
      if (access !== "free") return false
      if (flags && !shouldEnforceFreeLimits(flags)) return false
      return (
        upgrade?.presentProUpgrade({
          reason: { type: "limit", limit },
          retry,
        }) ?? false
      )
    },
    [access, flags, upgrade]
  )

  const presentFeature = useCallback(
    (feature: ProFeatureKind, retry?: ProUpgradeRetryAction) => {
      if (!shouldGateFeature(true)) return false
      return (
        upgrade?.presentProUpgrade({
          reason: { type: "feature", feature },
          retry,
        }) ?? false
      )
    },
    [shouldGateFeature, upgrade]
  )

  const fromError = useCallback(
    (error: unknown) => {
      if (access === "pro") return false
      if (flags && !shouldEnforceFreeLimits(flags)) return false
      const payload = parseProLimitPayload(error)
      if (!payload) return false
      if (access === "unknown") return false
      return (
        upgrade?.presentProUpgrade({
          reason: { type: "limit", limit: payload.limit },
        }) ?? false
      )
    },
    [access, flags, upgrade]
  )

  return {
    isPro,
    access,
    proFeatureUnlocked,
    showProLocks,
    entitlementStatus: (billing?.status ?? "ready") as BillingEntitlementStatus,
    refreshEntitlement: billing?.refresh ?? (async () => {}),
    snapshot: (billing?.snapshot ?? null) as BillingEntitlementSnapshot | null,
    billingProvider: (billing?.billingProvider ?? "unknown") as BillingProvider,
    appleSubscriptionLive: billing?.appleSubscriptionLive ?? false,
    flags: flags ?? null,
    shouldGateFeature,
    enforceFreeLimits: flags ? shouldEnforceFreeLimits(flags) : false,
    presentLimit,
    presentFeature,
    fromError,
    canPresentPaywall: upgrade?.canPresentPaywall ?? false,
  }
}

export type { ProGateReason, ProLimitKind, ProFeatureKind }
