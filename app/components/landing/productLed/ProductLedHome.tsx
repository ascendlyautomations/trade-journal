"use client"

/**
 * Public marketing homepage (v2 redesign).
 * Revert to LandingPageClient from app/(marketing)/page.tsx if needed.
 */

import "@/app/components/landing/v2/tradeTraxsHome.css"
import dynamic from "next/dynamic"
import type { ReactNode } from "react"

const ConfirmModal = dynamic(() => import("@/app/components/ui/ConfirmModal"))
const FeedbackModal = dynamic(() => import("@/app/components/ui/FeedbackModal"))
import LandingCommunityShell from "@/app/components/landing/v2/LandingCommunityShell"
import LandingFeaturesSection from "@/app/components/landing/v2/LandingFeaturesSection"
import LandingHeroSection from "@/app/components/landing/v2/LandingHeroSection"
import LandingJournalFeedFlowSection from "@/app/components/landing/v2/LandingJournalFeedFlowSection"
import LandingHowItWorks from "@/app/components/landing/v2/LandingHowItWorks"
import LandingIosSection from "@/app/components/landing/v2/LandingIosSection"
import { useLandingSignupActions } from "@/app/components/landing/v2/useLandingSignupActions"
import LandingComingSoonSection from "@/app/components/landing/LandingComingSoonSection"
import LandingAppStoreButton from "@/app/components/landing/v2/LandingAppStoreButton"
import LandingPlatformHubSection from "@/app/components/landing/v2/LandingPlatformHubSection"
import LandingFaqSection from "@/app/components/landing/LandingFaqSection"
import MarketingFooter from "@/app/components/marketing/MarketingFooter"
import { useEarlyAccessPromotion } from "@/lib/useEarlyAccessPromotion"

const LandingPricingSection = dynamic(
  () => import("@/app/components/landing/LandingPricingSection")
)

type ProductLedHomeProps = {
  featuredTradesSection: ReactNode
  weeklyTopTradersSection: ReactNode
  testimonialsSection: ReactNode
}

export default function ProductLedHome({
  featuredTradesSection,
  weeklyTopTradersSection,
  testimonialsSection,
}: ProductLedHomeProps) {
  const { enabled: earlyAccessPromotionEnabled } = useEarlyAccessPromotion()
  const {
    checkoutLoading,
    loading,
    trialCtaLabel,
    feedbackModalProps,
    loggedInDemoModalOpen,
    setLoggedInDemoModalOpen,
    loggedInTrialModalOpen,
    setLoggedInTrialModalOpen,
    handleStartTrial,
    handleExploreDemo,
    handleSubscribe,
    handleStartFreePlan,
    router,
  } = useLandingSignupActions()

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
          description="You already have TraxPro access. Return to the app to continue trading."
          cancelLabel="Cancel"
          confirmLabel="Return to App"
          onCancel={() => setLoggedInTrialModalOpen(false)}
          onConfirm={() => {
            setLoggedInTrialModalOpen(false)
            router.push("/dashboard")
          }}
        />
      ) : null}

      <div className="tt-home-v2">
        <LandingHeroSection
          trialCtaLabel={trialCtaLabel}
          checkoutLoading={checkoutLoading}
          loading={loading}
          onStartTrial={handleStartTrial}
          onExploreDemo={handleExploreDemo}
        />

        <LandingPlatformHubSection />
        <LandingJournalFeedFlowSection />
        <LandingHowItWorks />
        <LandingFeaturesSection />
        <LandingIosSection
          trialCtaLabel={trialCtaLabel}
          checkoutLoading={checkoutLoading}
          loading={loading}
          onStartTrial={handleStartTrial}
        />

        <LandingCommunityShell>
          {featuredTradesSection}
          {weeklyTopTradersSection}
        </LandingCommunityShell>

        {testimonialsSection}

        {!earlyAccessPromotionEnabled ? (
          <div className="tt-home-pricing">
            <LandingPricingSection
              checkoutLoading={checkoutLoading}
              onStartTrial={(interval) => void handleSubscribe(interval)}
              onStartFree={handleStartFreePlan}
            />
          </div>
        ) : null}

        <LandingComingSoonSection />
        <LandingFaqSection />

        <section className="tt-final-cta" aria-labelledby="final-cta-heading">
          <div className="tt-section-inner">
            <div className="tt-final-cta-inner">
              <h2 id="final-cta-heading">Bring Your Whole Trading Journey Into One Place.</h2>
              <p>
                One account on web and iPhone, log trades, review performance, track mindset, and
                share with the community when you are ready. Start free or explore the demo with
                sample data.
              </p>
              <div className="tt-final-cta-actions">
                <button
                  type="button"
                  className="tt-btn tt-btn-primary"
                  disabled={checkoutLoading || loading}
                  onClick={() => handleStartTrial()}
                >
                  {trialCtaLabel}
                </button>
                <button
                  type="button"
                  className="tt-btn tt-btn-secondary"
                  onClick={handleExploreDemo}
                >
                  Explore the Demo
                </button>
              </div>
              <div className="tt-final-cta-ios">
                <p className="tt-final-cta-ios-label">Native iOS, same trades, same sync as web</p>
                <LandingAppStoreButton surface="final_cta" />
              </div>
            </div>
          </div>
        </section>

        <MarketingFooter />
      </div>
    </>
  )
}
