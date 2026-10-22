"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import ProfileOnboarding from "@/app/components/ProfileOnboarding"
import { useUserProfile } from "@/lib/useUserProfile"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { markProfileUseFreeTier } from "@/lib/markFreeTierSignup"
import { supabase } from "@/lib/supabaseClient"
import { clearSignupFlow, clearSignupIntent } from "@/lib/signupFlow"
import { isEarlyAccessActive } from "@/lib/earlyAccess"
import { isSubscriptionExempt } from "@/lib/subscriptionAccess"
import {
  buildCreatorSignupPath,
  clearCreatorFlow,
  getPendingCreatorCode,
  redeemCreatorAccessCode,
} from "@/lib/creatorAccess"
import {
  clearWebSocialOAuthCallbackParams,
  readWebSocialOAuthCallbackError,
} from "@/lib/webSocialOAuth"

export default function OnboardingPage() {
  const router = useRouter()
  const { user, profile, loading, setProfile, refreshProfile } = useUserProfile()
  const [oauthCallbackError, setOauthCallbackError] = useState<string | null>(
    null
  )

  useEffect(() => {
    const oauthError = readWebSocialOAuthCallbackError()
    if (!oauthError) return
    setOauthCallbackError(oauthError)
    clearWebSocialOAuthCallbackParams()
  }, [])

  useEffect(() => {
    if (loading || user) return
    const pendingCreatorCode = getPendingCreatorCode()
    router.replace(
      pendingCreatorCode
        ? buildCreatorSignupPath(pendingCreatorCode)
        : "/login"
    )
  }, [loading, user, router])

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-sm text-gray-400">
        Loading…
      </div>
    )
  }

  if (!user) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-4 text-sm text-gray-400">
        {oauthCallbackError ? (
          <p className="max-w-md text-center text-sm text-red-300" role="alert">
            {oauthCallbackError}
          </p>
        ) : null}
        <p>Redirecting to sign in…</p>
      </div>
    )
  }

  return (
    <>
      {oauthCallbackError ? (
        <div
          className="border-b border-red-500/30 bg-red-950/40 px-4 py-3 text-center text-sm text-red-200"
          role="alert"
        >
          {oauthCallbackError}
        </div>
      ) : null}
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
            clearSignupFlow()
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

          if (
            !isEarlyAccessActive(accessProfile) &&
            !isSubscriptionExempt(accessProfile)
          ) {
            const result = await markProfileUseFreeTier(supabase, user.id)
            if (!result.ok) {
              console.error("Failed to mark free tier after onboarding:", result.error)
            }
          }

          clearSignupIntent()
          clearSignupFlow()
          router.replace("/dashboard")
          router.refresh()
        }}
      />
    </>
  )
}
