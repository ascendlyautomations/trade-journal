"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { ConfirmModal, FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets } from "@/lib/feedbackPresets"
import {
  ABOUT_CTA,
  ABOUT_DIFFERENTIATORS,
  ABOUT_FOUNDER_NOTE,
  ABOUT_HERO,
  ABOUT_LOOKING_AHEAD,
  ABOUT_MISSION,
  ABOUT_PAGE_EYEBROW,
  ABOUT_STORY,
} from "@/lib/aboutPageContent"
import { isDemoUserId } from "@/lib/demo/constants"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import { hasActiveMembership } from "@/lib/subscriptionAccess"
import { enterSignupFlow, setCheckoutBillingInterval } from "@/lib/signupFlow"
import { TRAXPRO_DEFAULT_BILLING_INTERVAL } from "@/lib/traxProBillingPlans"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  LANDING_BODY,
  LANDING_CARD_PADDING,
  LANDING_EYEBROW,
  LANDING_GLASS_SURFACE,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  LANDING_TITLE_GRADIENT,
} from "@/lib/landingPageUi"

function ProseSection({
  heading,
  paragraphs,
  centered = false,
}: {
  heading: string
  paragraphs: readonly string[]
  centered?: boolean
}) {
  return (
    <div className={centered ? "mx-auto max-w-3xl text-center" : "mx-auto max-w-3xl"}>
      <h2 className={LANDING_HEADLINE_SM}>{heading}</h2>
      <div className={`mt-6 space-y-4 ${LANDING_BODY}`}>
        {paragraphs.map((paragraph) => (
          <p key={paragraph}>{paragraph}</p>
        ))}
      </div>
    </div>
  )
}

export default function AboutPage() {
  const router = useRouter()
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user, profile, loading } = useUserProfile()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [loggedInDemoModalOpen, setLoggedInDemoModalOpen] = useState(false)
  const [loggedInTrialModalOpen, setLoggedInTrialModalOpen] = useState(false)

  const isAuthenticatedUser = !!user && !isDemoUserId(user.id)

  async function handleStartTrial() {
    if (isAuthenticatedUser) {
      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }
      if (profile && profileNeedsOnboarding(profile)) {
        router.push("/onboarding")
        return
      }
    }

    setCheckoutLoading(true)
    setCheckoutBillingInterval(TRAXPRO_DEFAULT_BILLING_INTERVAL)
    try {
      const {
        data: { user: authUser },
      } = await supabase.auth.getUser()

      if (!authUser) {
        enterSignupFlow()
        router.push("/login?tab=signup")
        return
      }

      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          userId: authUser.id,
          billingInterval: TRAXPRO_DEFAULT_BILLING_INTERVAL,
          referralCode:
            typeof window !== "undefined"
              ? localStorage.getItem("referral_code")
              : null,
        }),
      })

      const data = await res.json()
      if (data.url) {
        window.location.href = data.url
      } else {
        showPopup(
          feedbackPresets.subscriptionCheckoutFailed(
            data.error || "Checkout failed"
          )
        )
      }
    } catch (error) {
      console.error("Checkout error:", error)
      showPopup(feedbackPresets.subscriptionCheckoutFailed("Checkout failed"))
    } finally {
      setCheckoutLoading(false)
    }
  }

  function handleExploreDemo() {
    if (isAuthenticatedUser) {
      setLoggedInDemoModalOpen(true)
      return
    }
    router.push("/demo")
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
          className="pointer-events-none absolute inset-0 z-0 bg-[url('/images/hero-bg.png')] bg-cover bg-center bg-no-repeat opacity-[0.45] blur-[1px]"
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-0 z-[1] bg-gradient-to-b from-[#0a0f1c]/85 via-[#0a0f1c]/70 to-[#0a0f1c]/92"
          aria-hidden
        />

        <div className="relative z-10">
          <header className={`${LANDING_SECTION_SHELL} px-4 pt-28 text-center md:pt-36`}>
            <p className={LANDING_EYEBROW}>{ABOUT_PAGE_EYEBROW}</p>
            <h1 className="mt-4 text-4xl font-bold tracking-tight text-white md:text-5xl lg:text-6xl">
              {ABOUT_HERO.heading}
            </h1>
            <p className={`${LANDING_LEAD} mx-auto mt-6 max-w-3xl`}>
              {ABOUT_HERO.subheading}
            </p>
          </header>

          <section
            className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
            aria-labelledby="about-story-heading"
          >
            <div className={LANDING_SECTION_SHELL}>
              <div
                className={`${LANDING_GLASS_SURFACE} ${LANDING_CARD_PADDING} mx-auto max-w-3xl`}
              >
                <ProseSection
                  heading={ABOUT_STORY.heading}
                  paragraphs={ABOUT_STORY.paragraphs}
                />
              </div>
            </div>
          </section>

          <section
            className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
            aria-labelledby="about-mission-heading"
          >
            <div className={LANDING_SECTION_SHELL}>
              <ProseSection
                heading={ABOUT_MISSION.heading}
                paragraphs={ABOUT_MISSION.paragraphs}
                centered
              />
            </div>
          </section>

          <section
            className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
            aria-labelledby="about-different-heading"
          >
            <div className={LANDING_SECTION_SHELL}>
              <div className="mx-auto max-w-3xl text-center">
                <h2 id="about-different-heading" className={LANDING_HEADLINE_SM}>
                  What Makes{" "}
                  <span className={LANDING_TITLE_GRADIENT}>TradeTraxs</span> Different
                </h2>
              </div>
              <ul className="mx-auto mt-12 grid max-w-5xl gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {ABOUT_DIFFERENTIATORS.map((item) => (
                  <li
                    key={item.title}
                    className={`${LANDING_GLASS_SURFACE} ${LANDING_CARD_PADDING} flex flex-col`}
                  >
                    <span className="text-2xl" aria-hidden>
                      {item.icon}
                    </span>
                    <h3 className="mt-3 text-base font-semibold text-white">
                      {item.title}
                    </h3>
                    <p className={`mt-2 flex-1 text-sm leading-relaxed text-gray-400`}>
                      {item.description}
                    </p>
                  </li>
                ))}
              </ul>
            </div>
          </section>

          <section
            className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
            aria-labelledby="about-future-heading"
          >
            <div className={LANDING_SECTION_SHELL}>
              <ProseSection
                heading={ABOUT_LOOKING_AHEAD.heading}
                paragraphs={ABOUT_LOOKING_AHEAD.paragraphs}
                centered
              />
            </div>
          </section>

          <section className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}>
            <div className={LANDING_SECTION_SHELL}>
              <div
                className={`mx-auto max-w-3xl rounded-2xl border border-emerald-400/25 bg-gradient-to-br from-emerald-500/[0.08] via-white/[0.04] to-blue-500/[0.06] p-8 shadow-lg shadow-black/25 backdrop-blur-md md:p-10`}
              >
                <h2 className="text-xl font-bold text-white md:text-2xl">
                  {ABOUT_FOUNDER_NOTE.title}
                </h2>
                <div className={`mt-5 space-y-4 ${LANDING_BODY}`}>
                  {ABOUT_FOUNDER_NOTE.paragraphs.map((paragraph) => (
                    <p key={paragraph}>{paragraph}</p>
                  ))}
                </div>
                <p className="mt-8 text-sm font-semibold text-white">
                  — {ABOUT_FOUNDER_NOTE.signature}
                  <br />
                  <span className="font-normal text-gray-400">
                    {ABOUT_FOUNDER_NOTE.role}
                  </span>
                </p>
              </div>
            </div>
          </section>

          <section
            className={`${LANDING_SECTION_BORDER} px-4 py-20 md:py-24`}
            aria-labelledby="about-cta-heading"
          >
            <div className={`${LANDING_SECTION_SHELL} mx-auto max-w-4xl text-center`}>
              <div
                className={`${LANDING_GLASS_SURFACE} rounded-2xl border border-white/10 bg-gradient-to-br from-white/[0.07] via-white/[0.04] to-emerald-500/[0.06] px-6 py-12 shadow-lg shadow-black/25 md:px-10 md:py-14`}
              >
                <h2
                  id="about-cta-heading"
                  className="text-3xl font-extrabold tracking-tight text-white md:text-4xl"
                >
                  {ABOUT_CTA.heading}
                </h2>
                <div className="mt-8 flex flex-wrap justify-center gap-4">
                  <button
                    type="button"
                    disabled={checkoutLoading || loading}
                    onClick={() => void handleStartTrial()}
                    className="min-w-[220px] rounded-xl bg-emerald-500 px-8 py-3.5 font-semibold text-white hover:bg-emerald-600 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {checkoutLoading ? "Starting trial…" : ABOUT_CTA.trialLabel}
                  </button>
                  <button
                    type="button"
                    onClick={handleExploreDemo}
                    className="min-w-[220px] rounded-lg border border-white/20 px-8 py-3.5 font-semibold transition hover:bg-white/10"
                  >
                    {ABOUT_CTA.demoLabel}
                  </button>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </>
  )
}
