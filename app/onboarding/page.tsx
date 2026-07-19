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
import { isEarlyAccessActive } from "@/lib/earlyAccess"
import { isSubscriptionExempt } from "@/lib/subscriptionAccess"
import {
  buildCreatorSignupPath,
  clearCreatorFlow,
  getPendingCreatorCode,
  isCreatorFlowActive,
  redeemCreatorAccessCode,
} from "@/lib/creatorAccess"

export default function OnboardingPage() {
  const router = useRouter()
  const { user, profile, loading, setProfile, refreshProfile } = useUserProfile()

  useEffect(() => {
    if (loading || user) return
    const pendingCreatorCode = getPendingCreatorCode()
    router.replace(
      pendingCreatorCode
        ? buildCreatorSignupPath(pendingCreatorCode)
        : "/login"
    )
  }, [loading, user, router])

  useEffect(() => {
    if (loading || !user) return
    // Creator invite flow skips Choose Plan; still requires profile onboarding.
    if (isCreatorFlowActive() || getPendingCreatorCode()) return
    // Active Early Access users already skipped plan selection.
    if (isEarlyAccessActive(profile)) return
    if (!getSignupIntent()) {
      router.replace("/choose-plan")
    }
  }, [loading, user, profile, router])

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
      initialName={
        (typeof user.user_metadata?.full_name === "string"
          ? user.user_metadata.full_name
          : null) ||
        (typeof user.user_metadata?.name === "string"
          ? user.user_metadata.name
          : null)
      }
      initialBio={profile?.bio}
      initialTradingStyle={profile?.trading_style}
      initialTraderType={profile?.trader_type}
      initialPrimaryMarket={profile?.primary_market}
      initialStartedTrading={profile?.started_trading}
      initialAvatarUrl={profile?.avatar_url}
      onComplete={async (patch) => {
        notifyGettingStartedChecklistMaybeCompleted()

        const pendingCreatorCode = getPendingCreatorCode()
        if (pendingCreatorCode) {
          // Redeem BEFORE setProfile(onboarding_completed). Updating the client
          // profile first lets OnboardingGateShell navigate to /dashboard, then
          // SubscriptionGateShell bounce to /creator — a second concurrent redeem.
          const redeemResult = await redeemCreatorAccessCode(pendingCreatorCode)
          if (!redeemResult.ok) {
            console.error("[onboarding] creator redeem failed", {
              code: pendingCreatorCode,
              userId: user.id,
              status: redeemResult.status,
              error: redeemResult.error,
              message: redeemResult.message,
              result: redeemResult.result ?? null,
            })
            setProfile((p) => (p ? { ...p, ...patch } : p))
            router.replace(
              "/creator?code=" + encodeURIComponent(pendingCreatorCode)
            )
            return
          }
          clearCreatorFlow()
          clearSignupIntent()
          setProfile((p) =>
            p
              ? {
                  ...p,
                  ...patch,
                  ...redeemResult.entitlement,
                }
              : p
          )
          void refreshProfile()
          router.replace("/dashboard?creator=activated")
          return
        }

        const mergedProfile = profile
          ? { ...profile, ...patch }
          : { ...patch, id: user.id }
        setProfile((p) => (p ? { ...p, ...patch } : p))

        await refreshProfile()

        const { data: accessRow } = await supabase
          .from("profiles")
          .select(
            "use_free_tier, is_beta_tester, referred_by, is_pro, creator_access, subscription_status, trial_end, onboarding_completed, username, trader_type, trading_style, started_trading, early_access_enrolled_at, early_access_started_at, early_access_ends_at, early_access_status, early_access_campaign_id, early_access_enrollment_source"
          )
          .eq("id", user.id)
          .maybeSingle()

        const accessProfile = { ...mergedProfile, ...accessRow }

        // Early Access and other Pro exemptions must never open Stripe.
        if (
          isEarlyAccessActive(accessProfile) ||
          isSubscriptionExempt(accessProfile)
        ) {
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
