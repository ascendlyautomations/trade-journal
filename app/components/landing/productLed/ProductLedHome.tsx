"use client"

/**
 * Product-led homepage experiment.
 * The previous homepage remains in LandingPageClient.
 * Revert by rendering LandingPageClient from app/(marketing)/page.tsx.
 */

import "./productLedHome.css"
import dynamic from "next/dynamic"
import Image from "next/image"
import { useEffect, useState, type ReactNode } from "react"
import { useRouter } from "next/navigation"
import LandingAnalyticsShowcaseSection from "@/app/components/landing/LandingAnalyticsShowcaseSection"
import LandingComingSoonSection from "@/app/components/landing/LandingComingSoonSection"
import LandingComparisonSection from "@/app/components/LandingComparisonSection"
import LandingFaqSection from "@/app/components/landing/LandingFaqSection"
import LandingFeatureShowcaseSections from "@/app/components/LandingFeatureShowcaseSections"
import LandingFinalCtaSection from "@/app/components/LandingFinalCtaSection"
import LandingProblemSection from "@/app/components/landing/LandingProblemSection"
import MarketingFooter from "@/app/components/marketing/MarketingFooter"
import { useFeedbackPopup } from "@/app/components/ui/useFeedbackPopup"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { isDemoUserId } from "@/lib/demo/constants"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  clearSignupFlow,
  enterSignupFlow,
  getCheckoutBillingInterval,
  resolveSignupProfileSetupPath,
  setCheckoutBillingInterval,
} from "@/lib/signupFlow"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import {
  hasActiveMembership,
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
} from "@/lib/subscriptionAccess"
import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import { useEarlyAccessPromotion } from "@/lib/useEarlyAccessPromotion"
import { useUserProfile } from "@/lib/useUserProfile"

const ConfirmModal = dynamic(() => import("@/app/components/ui/ConfirmModal"))
const FeedbackModal = dynamic(() => import("@/app/components/ui/FeedbackModal"))
const LandingPricingSection = dynamic(
  () => import("@/app/components/landing/LandingPricingSection")
)

type ProductLedHomeProps = {
  featuredTradesSection: ReactNode
  testimonialsSection: ReactNode
}

export default function ProductLedHome({
  featuredTradesSection,
  testimonialsSection,
}: ProductLedHomeProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()
  const { enabled: earlyAccessPromotionEnabled } = useEarlyAccessPromotion()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [loggedInDemoModalOpen, setLoggedInDemoModalOpen] = useState(false)
  const [loggedInTrialModalOpen, setLoggedInTrialModalOpen] = useState(false)

  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)
  const hasActiveMembershipAccess =
    isAuthenticatedUser && !!profile && hasActiveMembership(profile)
  const trialCtaLabel = earlyAccessPromotionEnabled
    ? "Join Early Access"
    : `Start ${TRAXPRO_TRIAL_HEADLINE}!`

  useEffect(() => {
    if (hasActiveMembershipAccess) clearSignupFlow()
  }, [hasActiveMembershipAccess])

  useEffect(() => {
    if (loading || !isAuthenticatedUser) return
    if (isSubscriptionGateSuspended(user.id, { membershipReconciling })) return
    if (profile && profileNeedsOnboarding(profile)) {
      router.replace(resolveSignupProfileSetupPath())
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

      void startTraxProCheckout()
        .then((url) => {
          window.location.href = url
        })
        .catch((err) => {
          console.error("Referral checkout error:", err)
          showPopup({
            type: "error",
            message: "Checkout failed. Please try again.",
          })
        })
    }

    void runReferralCheckout()
  }, [user?.id, showPopup])

  const handleStartTrial = () => {
    if (isAuthenticatedUser) {
      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }
      if (profile && profileNeedsOnboarding(profile)) {
        router.push(resolveSignupProfileSetupPath())
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
        router.push(resolveSignupProfileSetupPath())
        return
      }
      if (profile && needsSubscriptionCheckout(profile)) {
        router.push("/finish-trial")
        return
      }
      const url = await startTraxProCheckout({ billingInterval: interval })
      window.location.href = url
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
      {feedbackModalProps.isOpen ? <FeedbackModal {...feedbackModalProps} /> : null}
      {loggedInDemoModalOpen ? (
        <ConfirmModal
          open
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
      ) : null}
      {loggedInTrialModalOpen ? (
        <ConfirmModal
          open
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
      ) : null}

      <div className="tt-home-product">
        <section className="tt-home-hero" aria-labelledby="home-heading">
          <div className="tt-home-shell tt-home-shell-wide tt-home-hero-grid">
            <div className="tt-home-hero-copy">
              <p className="tt-home-kicker">TradeTraxs</p>
              <h1 id="home-heading">
                The First Social Platform
                <span>Built for Traders.</span>
              </h1>
              <p className="tt-home-lede">
                TradeTraxs brings together journaling, analytics, community, education, and AI
                into one connected home where traders can learn, improve, and grow together.
              </p>
              <div className="tt-home-actions">
                <button
                  type="button"
                  className="tt-home-btn tt-home-btn-primary"
                  disabled={checkoutLoading || loading}
                  onClick={() => void handleSubscribe()}
                >
                  {checkoutLoading ? "Starting trial…" : trialCtaLabel}
                </button>
                <button
                  type="button"
                  className="tt-home-btn tt-home-btn-secondary"
                  onClick={handleExploreDemo}
                >
                  Explore the Demo
                </button>
              </div>
            </div>

            <div className="tt-home-stage">
              <figure className="tt-home-shot tt-home-shot-dash">
                <Image
                  src="/images/dashboard.webp"
                  alt="TradeTraxs dashboard with equity curve, performance stats, and recent trades"
                  fill
                  priority
                  quality={72}
                  sizes="(max-width: 1199px) 100vw, 720px"
                />
              </figure>
              <figure className="tt-home-shot tt-home-shot-feed">
                <Image
                  src="/images/social-feed.webp"
                  alt="A trade posted to the TradeTraxs feed"
                  fill
                  loading="eager"
                  quality={70}
                  sizes="280px"
                />
              </figure>
              <figure className="tt-home-shot tt-home-shot-prop">
                <Image
                  src="/images/Prop_Firm_Mode.webp"
                  alt="Prop Firm Mode with equity, drawdown, and payout progress"
                  fill
                  loading="eager"
                  quality={70}
                  sizes="420px"
                />
              </figure>
            </div>
          </div>
        </section>

        <div className="tt-home-story">
          <LandingProblemSection />
          <LandingFeatureShowcaseSections />
          <LandingAnalyticsShowcaseSection />
          <LandingComparisonSection />
          {featuredTradesSection}
          {!earlyAccessPromotionEnabled ? (
            <div className="tt-home-pricing">
              <LandingPricingSection
                checkoutLoading={checkoutLoading}
                onStartTrial={(interval) => void handleSubscribe(interval)}
                onStartFree={() => {
                  enterSignupFlow()
                  router.push("/login?tab=signup")
                }}
              />
            </div>
          ) : null}
          {testimonialsSection}
          <LandingFaqSection />
          <LandingComingSoonSection />
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
