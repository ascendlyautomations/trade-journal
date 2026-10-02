"use client"

import { useCallback } from "react"
import { useProUpgradeOptional } from "@/app/components/monetization/ProUpgradeProvider"
import { isProActive } from "./subscription"
import type { ProFeatureKind, ProGateReason, ProLimitKind } from "./proGateReason"
import { parseProLimitPayload } from "./proGateReason"
import { shouldEnforceFreeLimits } from "./proMonetizationPolicy"
import type { ProUpgradeRetryAction } from "./proUpgradeContinuation"

type ProfileLike = Parameters<typeof isProActive>[0]

export function useProGate(profile: ProfileLike) {
  const upgrade = useProUpgradeOptional()
  const isPro = isProActive(profile)
  const flags = upgrade?.flags

  const shouldGateFeature = useCallback(
    (featureIsProOnly = true) => {
      if (!featureIsProOnly || isPro) return false
      return upgrade?.shouldGateProFeature(isPro) ?? false
    },
    [isPro, upgrade]
  )

  const presentLimit = useCallback(
    (limit: ProLimitKind, retry?: ProUpgradeRetryAction) => {
      if (isPro) return false
      if (flags && !shouldEnforceFreeLimits(flags)) return false
      return (
        upgrade?.presentProUpgrade({
          reason: { type: "limit", limit },
          retry,
        }) ?? false
      )
    },
    [isPro, flags, upgrade]
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
      if (isPro) return false
      if (flags && !shouldEnforceFreeLimits(flags)) return false
      const payload = parseProLimitPayload(error)
      if (!payload) return false
      return (
        upgrade?.presentProUpgrade({
          reason: { type: "limit", limit: payload.limit },
        }) ?? false
      )
    },
    [isPro, flags, upgrade]
  )

  return {
    isPro,
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
