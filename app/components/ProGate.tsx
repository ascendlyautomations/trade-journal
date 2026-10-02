"use client"

import React from "react"
import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"
import { useProGate } from "@/lib/useProGate"
import { useUserProfile } from "@/lib/useUserProfile"
import type { ProFeatureKind } from "@/lib/proGateReason"

type ProGateProps = {
  isPro?: boolean
  feature?: ProFeatureKind
  children: React.ReactNode
}

export default function ProGate({
  isPro: isProProp,
  feature = "generic",
  children,
}: ProGateProps) {
  const { profile } = useUserProfile()
  const { shouldGateFeature, presentFeature, isPro: isProFromProfile } =
    useProGate(profile)
  const isPro = isProProp ?? isProFromProfile

  if (isPro || !shouldGateFeature(true)) {
    return <>{children}</>
  }

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-gray-100">
      <h2 className="mb-2 text-xl font-semibold">Upgrade to {TRADETRAXS_PRO_PLAN.name}</h2>
      <p className="mb-4 text-sm text-gray-300">
        This feature is available with {TRADETRAXS_PRO_PLAN.name}.
      </p>
      <button
        type="button"
        onClick={() => presentFeature(feature)}
        className="rounded-lg bg-blue-500 px-4 py-2 font-semibold text-white hover:bg-blue-600"
      >
        View plans
      </button>
    </div>
  )
}
