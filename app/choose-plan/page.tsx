"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import SignupPlanPicker from "@/app/components/SignupPlanPicker"
import { useUserProfile } from "@/lib/useUserProfile"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import { isEarlyAccessActive } from "@/lib/earlyAccess"
import { resolvePostAuthAppPath } from "@/lib/subscriptionAccess"
import {
  enterSignupFlow,
  getSignupIntent,
  setCheckoutBillingInterval,
  setSignupIntent,
} from "@/lib/signupFlow"
import { getPendingCreatorCode, isCreatorFlowActive, buildCreatorSignupPath } from "@/lib/creatorAccess"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"

export default function ChoosePlanPage() {
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()
  const [billingInterval, setBillingInterval] = useState<TraxProBillingIntervalId>(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )
  const [continuing, setContinuing] = useState(false)

  useEffect(() => {
    if (loading) return
    if (!user) {
      const pendingCreatorCode = getPendingCreatorCode()
      router.replace(
        pendingCreatorCode
          ? buildCreatorSignupPath(pendingCreatorCode)
          : "/login?tab=signup"
      )
      return
    }
    if (!profile) return

    if (isEarlyAccessActive(profile)) {
      router.replace(
        profileNeedsOnboarding(profile) ? "/onboarding" : "/dashboard"
      )
      return
    }

    if (!profileNeedsOnboarding(profile)) {
      router.replace(resolvePostAuthAppPath(profile))
      return
    }

    // Creator invite: profile setup only — never Choose Plan / billing.
    if (isCreatorFlowActive() || getPendingCreatorCode()) {
      router.replace("/onboarding")
      return
    }

    const intent = getSignupIntent()
    if (intent) {
      router.replace("/onboarding")
    }
  }, [loading, user, profile, router])

  function handleBillingIntervalChange(interval: TraxProBillingIntervalId) {
    setBillingInterval(interval)
    setCheckoutBillingInterval(interval)
  }

  function continueWithPlan(intent: "trial" | "free") {
    if (continuing) return
    setContinuing(true)
    setSignupIntent(intent)
    enterSignupFlow()
    if (intent === "trial") {
      setCheckoutBillingInterval(billingInterval)
    }
    router.push("/onboarding")
  }

  if (loading || !user) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        Loading…
      </div>
    )
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center px-4 py-10 text-white">
      <img
        src="/tradetrax-bg.webp"
        alt=""
        className="absolute inset-0 h-full w-full object-cover"
        aria-hidden
      />
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" aria-hidden />

      <div className="relative z-10 w-full max-w-md rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl md:py-6 md:px-8">
        <h1 className="mb-2 text-center text-2xl font-semibold text-blue-300">
          Choose how you&apos;d like to get started
        </h1>
        <p className="mb-6 text-center text-sm text-gray-300 md:mb-4">
          Pick a plan to continue setting up your account. Nothing is selected until
          you choose.
        </p>

        <SignupPlanPicker
          billingInterval={billingInterval}
          onBillingIntervalChange={handleBillingIntervalChange}
          onSelectTrial={() => continueWithPlan("trial")}
          onSelectFree={() => continueWithPlan("free")}
          disabled={continuing}
          loading={continuing}
          billingPickerName="choose-plan-billing"
        />
      </div>
    </div>
  )
}
