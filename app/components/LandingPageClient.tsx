"use client"

import { useEffect, useState, type ReactNode } from "react"
import { useRouter } from "next/navigation"
import LandingComparisonSection from "./LandingComparisonSection"
import LandingFeatureShowcaseSections from "./LandingFeatureShowcaseSections"
import LandingFinalCtaSection from "./LandingFinalCtaSection"
import LandingProblemSection from "./landing/LandingProblemSection"
import LandingAnalyticsShowcaseSection from "./landing/LandingAnalyticsShowcaseSection"
import LandingPricingSection from "./landing/LandingPricingSection"
import LandingFaqSection from "./landing/LandingFaqSection"
import { supabase } from "../../lib/supabaseClient"
import { ConfirmModal, FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import MarketingFooter from "./marketing/MarketingFooter"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import { useUserProfile } from "@/lib/useUserProfile"
import { isDemoUserId } from "@/lib/demo/constants"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  hasActiveMembership,
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
} from "@/lib/subscriptionAccess"
import { clearSignupFlow, enterSignupFlow, getCheckoutBillingInterval, setCheckoutBillingInterval } from "@/lib/signupFlow"
import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"

type LandingPageClientProps = {
  featuredTradesSection: ReactNode
  testimonialsSection: ReactNode
}

export default function LandingPageClient({
  featuredTradesSection,
  testimonialsSection,
}: LandingPageClientProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [loggedInDemoModalOpen, setLoggedInDemoModalOpen] = useState(false)
  const [loggedInTrialModalOpen, setLoggedInTrialModalOpen] = useState(false)

  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)
  const hasActiveMembershipAccess =
    isAuthenticatedUser && !!profile && hasActiveMembership(profile)
  const trialCtaLabel = `Start ${TRAXPRO_TRIAL_HEADLINE}!`

  useEffect(() => {
    if (hasActiveMembershipAccess) clearSignupFlow()
  }, [hasActiveMembershipAccess])

  useEffect(() => {
    if (loading || !isAuthenticatedUser) return
    if (isSubscriptionGateSuspended(user.id, { membershipReconciling })) return
    if (profile && profileNeedsOnboarding(profile)) {
      router.replace("/onboarding")
      return
    }
    if (profile && needsSubscriptionCheckout(profile)) {
      router.replace("/finish-trial")
    }
  }, [loading, isAuthenticatedUser, user?.id, profile, router, membershipReconciling])

  function handleExploreDemo() {
    if (isAuthenticatedUser) {
      setLoggedInDemoModalOpen(true)
      return
    }
    router.push("/demo")
  }

  useEffect(() => {
    if (typeof window === "undefined") return

    const runReferralCheckout = async () => {
      const params = new URLSearchParams(window.location.search)
      const ref = params.get("ref")

      if (!ref || isBetaReferralRef(ref)) return

      if (!user?.id) return

      fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId: user.id,
          referralCode: localStorage.getItem("referral_code"),
        }),
      })
        .then(async (res) => {
          const data = await res.json()
          if (!res.ok) {
            throw new Error(data?.error || "Referral checkout failed")
          }
          return data
        })
        .then((data) => {
          if (data.url) {
            window.location.href = data.url
          }
        })
        .catch((err) => {
          console.error("Referral checkout error:", err)
        })
    }

    void runReferralCheckout()
  }, [user?.id])

  const handleStartTrial = () => {
    if (isAuthenticatedUser) {
      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }
      if (profile && profileNeedsOnboarding(profile)) {
        router.push("/onboarding")
        return
      }
      if (profile && needsSubscriptionCheckout(profile)) {
        router.push("/finish-trial")
        return
      }
      router.push("/dashboard")
      return
    }

    const qs = new URLSearchParams(window.location.search)
    const ref = qs.get("ref")
    const next = new URLSearchParams({ tab: "signup" })
    if (ref) next.set("ref", ref)
    enterSignupFlow()
    router.push(`/login?${next.toString()}`)
  }

  const handleSubscribe = async (billingInterval?: TraxProBillingIntervalId) => {
    const interval = billingInterval ?? getCheckoutBillingInterval()
    setCheckoutBillingInterval(interval)
    setCheckoutLoading(true)
    try {
      if (!user?.id) {
        handleStartTrial()
        return
      }

      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }

      if (profile && profileNeedsOnboarding(profile)) {
        router.push("/onboarding")
        return
      }

      if (profile && needsSubscriptionCheckout(profile)) {
        router.push("/finish-trial")
        return
      }

      const {
        data: { session },
      } = await supabase.auth.getSession()
      const accessToken = session?.access_token

      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        },
        body: JSON.stringify({
          userId: user.id,
          billingInterval: interval,
          referralCode: localStorage.getItem("referral_code"),
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        throw new Error(data?.error || "Checkout failed")
      }

      if (data.url) {
        window.location.href = data.url
      }
    } catch (err) {
      console.error("Checkout error:", err)
      showPopup({
        type: "error",
        message: "Checkout failed. Please try again.",
      })
    } finally {
      setCheckoutLoading(false)
    }
  }

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <ConfirmModal
        open={loggedInDemoModalOpen}
        title="Already Logged In"
        description="You're already signed in. Please sign out first if you'd like to explore the demo experience."
        cancelLabel="Cancel"
        confirmLabel="Return to App"
        onCancel={() => setLoggedInDemoModalOpen(false)}
        onConfirm={() => {
          setLoggedInDemoModalOpen(false)
          router.push("/dashboard")
        }}
      />
      <ConfirmModal
        open={loggedInTrialModalOpen}
        title="You're Already Covered"
        description="You already have an active 14-day free trial or subscription. Return to the app to continue trading."
        cancelLabel="Cancel"
        confirmLabel="Return to App"
        onCancel={() => setLoggedInTrialModalOpen(false)}
        onConfirm={() => {
          setLoggedInTrialModalOpen(false)
          router.push("/dashboard")
        }}
      />

      <div className="relative min-h-screen overflow-hidden text-gray-100">
        <div
          className="pointer-events-none absolute inset-0 z-0 bg-[url('/images/hero-bg.png')] bg-cover bg-center bg-no-repeat opacity-[0.52] blur-[1px]"
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-0 z-[1] bg-gradient-to-b from-[#0a0f1c]/80 via-[#0a0f1c]/60 to-[#0a0f1c]/90"
          aria-hidden
        />

        <div className="relative z-10">
          <div className="relative flex flex-col items-center px-4 pt-24 pb-14 text-center md:px-6 md:pt-36 md:pb-28">
            <div
              className="pointer-events-none absolute inset-0 bg-gradient-to-r from-blue-500/10 via-emerald-500/10 to-transparent blur-3xl opacity-30"
              aria-hidden
            />

            <h1 className="z-10 mb-4 text-3xl font-bold leading-tight sm:text-4xl md:mb-6 md:text-6xl lg:text-7xl">
              The First Social Platform
              <br />
              <span className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
                Built for Traders.
              </span>
            </h1>

            <p className="z-10 mb-6 max-w-2xl text-base leading-relaxed text-gray-400 md:mb-10 md:text-xl">
              TradeTraxs brings together journaling, analytics, community, education, and AI into
              one connected home where traders can learn, improve, and grow together.
            </p>

            <div className="z-10 flex flex-wrap justify-center gap-3 md:gap-4">
              <button
                type="button"
                disabled={checkoutLoading || loading}
                onClick={() => void handleSubscribe()}
                className="min-w-[200px] rounded-xl bg-emerald-500 px-6 py-3 font-semibold text-white hover:bg-emerald-600 disabled:cursor-not-allowed disabled:opacity-60 md:min-w-[220px] md:px-8 md:py-3.5"
              >
                {checkoutLoading ? "Starting trial…" : trialCtaLabel}
              </button>

              <button
                type="button"
                onClick={handleExploreDemo}
                className="min-w-[200px] rounded-lg border border-white/20 px-6 py-3 font-semibold transition hover:bg-white/10 md:min-w-[220px] md:px-8 md:py-3.5"
              >
                Explore the Demo
              </button>
            </div>
          </div>

          <LandingProblemSection />
          <LandingFeatureShowcaseSections />
          <LandingAnalyticsShowcaseSection />
          <LandingComparisonSection />
          {featuredTradesSection}
          <LandingPricingSection
            checkoutLoading={checkoutLoading}
            onStartTrial={(interval) => void handleSubscribe(interval)}
            onStartFree={() => {
              enterSignupFlow()
              router.push("/login?tab=signup")
            }}
          />
          {testimonialsSection}
          <LandingFaqSection />
          <LandingFinalCtaSection
            checkoutLoading={checkoutLoading}
            onStartTrial={() => void handleSubscribe()}
          />

          <MarketingFooter />
        </div>
      </div>
    </>
  )
}
