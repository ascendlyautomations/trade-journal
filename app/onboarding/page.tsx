"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import ProfileOnboarding from "@/app/components/ProfileOnboarding"
import { useUserProfile } from "@/lib/useUserProfile"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import { markProfileUseFreeTier } from "@/lib/markFreeTierSignup"
import { supabase } from "@/lib/supabaseClient"
import {
  clearSignupIntent,
  getCheckoutBillingInterval,
  getSignupIntent,
} from "@/lib/signupFlow"
import { isSubscriptionExempt } from "@/lib/subscriptionAccess"

export default function OnboardingPage() {
  const router = useRouter()
  const { user, profile, loading, setProfile, refreshProfile } = useUserProfile()

  useEffect(() => {
    if (!loading && !user) {
      router.replace("/login")
    }
  }, [loading, user, router])

  useEffect(() => {
    if (loading || !user) return
    if (!getSignupIntent()) {
      router.replace("/choose-plan")
    }
  }, [loading, user, router])

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        Loading…
      </div>
    )
  }

  if (!user) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        Redirecting to sign in…
      </div>
    )
  }

  return (
    <ProfileOnboarding
      userId={user.id}
      initialUsername={profile?.username}
      initialName={null}
      initialBio={profile?.bio}
      initialTradingStyle={profile?.trading_style}
      initialTraderType={profile?.trader_type}
      initialPrimaryMarket={profile?.primary_market}
      initialStartedTrading={profile?.started_trading}
      initialAvatarUrl={profile?.avatar_url}
      onComplete={async (patch) => {
        const mergedProfile = profile ? { ...profile, ...patch } : { ...patch, id: user.id }
        setProfile((p) => (p ? { ...p, ...patch } : p))
        notifyGettingStartedChecklistMaybeCompleted()
        await refreshProfile()

        const { data: accessRow } = await supabase
          .from("profiles")
          .select(
            "use_free_tier, is_beta_tester, referred_by, is_pro, subscription_status, trial_end, onboarding_completed, username, trader_type, trading_style, started_trading"
          )
          .eq("id", user.id)
          .maybeSingle()

        const accessProfile = { ...mergedProfile, ...accessRow }

        if (isSubscriptionExempt(accessProfile)) {
          clearSignupIntent()
          router.replace("/dashboard")
          router.refresh()
          return
        }

        const signupIntent = getSignupIntent()
        if (!signupIntent) {
          router.replace("/choose-plan")
          router.refresh()
          return
        }
        if (signupIntent === "free") {
          const result = await markProfileUseFreeTier(supabase, user.id)
          if (!result.ok) {
            console.error("Failed to mark free tier:", result.error)
          }
          clearSignupIntent()
          router.replace("/dashboard")
          router.refresh()
          return
        }

        try {
          const checkoutUrl = await startTraxProCheckout({
            billingInterval: getCheckoutBillingInterval(),
          })
          window.location.href = checkoutUrl
        } catch (err) {
          console.error("Checkout after onboarding failed:", err)
          router.replace("/finish-trial")
          router.refresh()
        }
      }}
    />
  )
}
