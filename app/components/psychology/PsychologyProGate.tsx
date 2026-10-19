"use client"

import { useEffect, useRef, type ReactNode } from "react"
import { useProUpgradeOptional } from "@/app/components/monetization/ProUpgradeProvider"
import { useUserProfile } from "@/lib/useUserProfile"
import { useProGate } from "@/lib/useProGate"

type PsychologyProGateProps = {
  children: ReactNode
}

/** Mirrors iOS premium psychology + AI route gating. */
export default function PsychologyProGate({ children }: PsychologyProGateProps) {
  const { profile } = useUserProfile()
  const { proFeatureUnlocked, presentFeature } = useProGate(profile)
  const upgrade = useProUpgradeOptional()
  const didPresentRef = useRef(false)

  useEffect(() => {
    if (proFeatureUnlocked) {
      didPresentRef.current = false
      return
    }
    if (didPresentRef.current) return
    didPresentRef.current = true
    presentFeature("premium_analytics")
  }, [presentFeature, proFeatureUnlocked])

  if (!proFeatureUnlocked) {
    return (
      <div
        className="rounded-xl border border-white/10 bg-white/5 p-6"
        data-testid="dashboard.psychology.upgrade.traxpro"
      >
        <h2 className="text-lg font-semibold text-white">TraxPro psychology analytics</h2>
        <p className="mt-2 text-sm text-gray-400">
          Advanced psychology analytics and coaching are included with TraxPro.
        </p>
        <button
          type="button"
          className="mt-4 w-full rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white"
          onClick={() =>
            upgrade?.presentProUpgrade({
              reason: { type: "feature", feature: "premium_analytics" },
            })
          }
        >
          Upgrade to TraxPro
        </button>
      </div>
    )
  }

  return <>{children}</>
}
