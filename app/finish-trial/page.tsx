"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/app/components/ui"
import { useUserProfile } from "@/lib/useUserProfile"
import { supabase } from "@/lib/supabaseClient"
import { markProfileUseFreeTier } from "@/lib/markFreeTierSignup"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import {
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
  resolvePostAuthAppPath,
} from "@/lib/subscriptionAccess"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"
import TraxProBillingIntervalPicker from "@/app/components/TraxProBillingIntervalPicker"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import { setCheckoutBillingInterval } from "@/lib/signupFlow"
import { LOADING_COPY } from "@/lib/loadingCopy"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export default function FinishTrialPage() {
  const router = useRouter()
  const { user, profile, loading, membershipReconciling, refreshProfile } =
    useUserProfile()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [continueLoading, setContinueLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [billingInterval, setBillingInterval] = useState<TraxProBillingIntervalId>(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )

  useEffect(() => {
    if (loading) return
    if (!user) {
      router.replace("/login?tab=signup")
      return
    }
    if (isSubscriptionGateSuspended(user.id, { membershipReconciling })) {
      router.replace("/dashboard")
      return
    }
    if (!profile) return

    const destination = resolvePostAuthAppPath(profile)
    if (destination === "/choose-plan" || destination === "/onboarding") {
      router.replace(destination)
      return
    }
    if (destination === "/dashboard") {
      router.replace("/dashboard")
    }
  }, [loading, user, profile, router, membershipReconciling])

  async function handleStartTrial() {
    setCheckoutLoading(true)
    setError(null)
    setCheckoutBillingInterval(billingInterval)
    try {
      const url = await startTraxProCheckout({ billingInterval })
      window.location.href = url
    } catch (err) {
      console.error("[finish-trial] checkout failed", err)
      setError(
        toUserFacingErrorMessage(err, "Checkout failed. Please try again.")
      )
      setCheckoutLoading(false)
    }
  }

  async function handleContinueFree() {
    if (!user?.id || continueLoading || checkoutLoading) return
    setContinueLoading(true)
    setError(null)
    try {
      const result = await markProfileUseFreeTier(supabase, user.id)
      if (!result.ok) {
        setError(
          result.error ?? "Could not continue on Free. Please try again."
        )
        setContinueLoading(false)
        return
      }
      await refreshProfile()
      router.replace("/dashboard")
    } catch (err) {
      console.error("[finish-trial] continue free failed", err)
      setError(toUserFacingErrorMessage(err))
      setContinueLoading(false)
    }
  }

  if (loading || !user || !profile || !needsSubscriptionCheckout(profile)) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        {LOADING_COPY.finishTrial}
      </div>
    )
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center px-4 py-16 text-white">
      <img
        src="/tradetrax-bg.webp"
        alt=""
        className="absolute inset-0 h-full w-full object-cover"
        aria-hidden
      />
      <div className="absolute inset-0 bg-black/70" aria-hidden />

      <div className="relative z-10 w-full max-w-lg rounded-2xl border border-white/10 bg-[#0f172a]/95 p-8 shadow-2xl backdrop-blur-md">
        <p className="text-sm font-semibold uppercase tracking-wide text-emerald-300">
          You&apos;re all set
        </p>
        <h1 className="mt-2 text-3xl font-bold text-blue-300">Your profile is ready</h1>
        <p className="mt-4 text-sm leading-relaxed text-gray-300">
          Continue on the Free plan anytime, or start your{" "}
          {TRAXPRO_TRIAL_HEADLINE.toLowerCase()} to unlock {TRADETRAXS_PRO_PLAN.name} —{" "}
          {TRADETRAXS_PRO_PLAN.description}
        </p>

        <div className="mt-6">
          <TraxProBillingIntervalPicker
            value={billingInterval}
            onChange={(interval) => {
              setBillingInterval(interval)
              setCheckoutBillingInterval(interval)
            }}
            disabled={checkoutLoading || continueLoading}
            name="finish-trial-billing"
          />
        </div>

        {error ? (
          <p className="mt-4 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
            {error}
          </p>
        ) : null}

        <div className="mt-8 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <Button
            type="button"
            variant="secondary"
            disabled={checkoutLoading || continueLoading}
            onClick={() => void handleContinueFree()}
          >
            {continueLoading ? "Continuing…" : "Continue to Dashboard"}
          </Button>
          <Button
            type="button"
            variant="accent"
            disabled={checkoutLoading || continueLoading}
            onClick={() => void handleStartTrial()}
          >
            {checkoutLoading ? "Starting trial…" : "Upgrade to Pro"}
          </Button>
        </div>

        <p className="mt-4 text-center text-xs text-gray-500">
          No pressure — upgrade whenever you&apos;re ready.
        </p>
      </div>
    </div>
  )
}
