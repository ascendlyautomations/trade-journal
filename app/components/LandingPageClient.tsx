"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import PublicNavbar from "./PublicNavbar"
import LandingComparisonSection from "./LandingComparisonSection"
import LandingFeatureShowcaseSections from "./LandingFeatureShowcaseSections"
import LandingCommunitySection from "./LandingCommunitySection"
import LandingTradingContentSection from "./LandingTradingContentSection"
import LandingFeatureGridSection from "./LandingFeatureGridSection"
import LandingFinalCtaSection from "./LandingFinalCtaSection"
import { supabase } from "../../lib/supabaseClient"
import {
  LANDING_CARD_FULL,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_TITLE_GRADIENT,
  useLandingReveal,
} from "@/lib/landingPageUi"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { LEGAL_CONTACT_EMAIL } from "@/lib/legal/contact"

const PRICING_FREE_FEATURES = [
  "Track your trades",
  "1 trading account",
  "Basic dashboard insights",
  "Trading calendar access",
  "Public profile",
  "Community feed access",
  "View and interact with other traders",
  "Basic messaging (limited)",
] as const

const PRICING_PRO_FEATURES = [
  "Unlimited trading accounts",
  "Full performance dashboard",
  "Advanced analytics & stats",
  "AI Trade Analyst (automated insights)",
  "Session + strategy breakdowns",
  "Trading calendar with full analytics",
  "Enhanced public profile & stats",
  "Full messaging & networking",
  "Priority community features",
  "Track what actually makes you money",
] as const

const HOW_STEPS = [
  {
    title: "1. Log Your Trades",
    body: "Seconds per entry: P&L, risk/reward, session tags, notes that stick.",
  },
  {
    title: "2. See Exactly What You Saw",
    body: "Screenshots bring levels, zones, and context back—the way you saw them live.",
  },
  {
    title: "3. Fix Mistakes & Improve Faster",
    body: "Spot costly patterns—overtrading, loose entries, weak risk—and correct with data, not guesses.",
  },
] as const

export default function LandingPageClient() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const howItWorks = useLandingReveal()

  useEffect(() => {
    if (typeof window === "undefined") return

    const runReferralCheckout = async () => {
      const params = new URLSearchParams(window.location.search)
      const ref = params.get("ref")

      if (!ref) return

      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        return
      }

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
  }, [])

  const handleSubscribe = async () => {
    setCheckoutLoading(true)
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        const qs = new URLSearchParams(window.location.search)
        const ref = qs.get("ref")
        const next = new URLSearchParams({ next: "checkout" })
        if (ref) next.set("ref", ref)
        router.push(`/login?${next.toString()}`)
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
      <PublicNavbar />
      <FeedbackModal {...feedbackModalProps} />

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
        <div className="relative flex flex-col items-center px-6 pt-20 pb-14 text-center md:pb-20">
          <div className="absolute inset-0 bg-gradient-to-r from-blue-500/10 via-emerald-500/10 to-transparent blur-3xl opacity-30" />

          <h1 className="text-6xl font-bold mb-6 leading-tight z-10">
            Trade Smarter.
            <br />
            <span className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Not Harder.
            </span>
          </h1>

          <p className="text-lg text-gray-400 max-w-xl mb-10 z-10 leading-relaxed">
            Log every trade. See the full picture. Tighten your edge—fast.
            <br />
            <span className="text-gray-500">Built for traders who treat this like a craft.</span>
          </p>

          <div className="flex flex-wrap justify-center gap-4 z-10">
            <button
              type="button"
              disabled={checkoutLoading}
              onClick={() => void handleSubscribe()}
              className="bg-emerald-500 hover:bg-emerald-600 disabled:opacity-60 disabled:cursor-not-allowed px-6 py-3 rounded-xl font-semibold text-white"
            >
              {checkoutLoading ? "Starting trial..." : "Start 14-Day Free Trial"}
            </button>

            <button
              type="button"
              onClick={() => router.push("/app")}
              className="border border-white/20 px-6 py-3 rounded-lg hover:bg-white/10 transition"
            >
              Preview Site
            </button>
          </div>

          <div className="mt-6 flex flex-wrap justify-center gap-x-6 gap-y-2 z-10">
            <Link
              href="/explore"
              className="text-sm font-medium text-blue-300 transition hover:text-blue-200"
            >
              Explore Traders →
            </Link>
            <Link
              href="/leaderboard"
              className="text-sm font-medium text-blue-300 transition hover:text-blue-200"
            >
              View Leaderboard →
            </Link>
          </div>
        </div>

        <section
          ref={howItWorks.ref}
          id="how"
          className="text-center px-6 pt-12 pb-24 md:pt-16 md:pb-24"
        >
          <h2
            className={`text-4xl font-extrabold mb-12 md:mb-14 text-white drop-shadow-lg tracking-tight ${LANDING_REVEAL_TRANSITION} ${howItWorks.visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
          >
            How It Works
          </h2>

          <div className="grid md:grid-cols-3 gap-6 md:gap-8 max-w-6xl mx-auto">
            {HOW_STEPS.map((step, i) => (
              <div
                key={step.title}
                className={`flex flex-col text-left ${LANDING_CARD_FULL} p-8 ${LANDING_REVEAL_TRANSITION} ${howItWorks.visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
                style={{
                  transitionDelay: howItWorks.visible ? `${i * 75}ms` : "0ms",
                }}
              >
                <h3 className="text-xl font-semibold mb-3 text-emerald-300">{step.title}</h3>
                <p className="text-gray-200 text-sm leading-relaxed">{step.body}</p>
              </div>
            ))}
          </div>
        </section>

        <LandingCommunitySection />

        <LandingTradingContentSection />

        <LandingFeatureGridSection />

        <LandingComparisonSection />

        <LandingFeatureShowcaseSections />

        <section
          id="pricing"
          className="border-t border-white/10 px-6 py-24 md:py-28"
          aria-labelledby="pricing-heading"
        >
          <div className="mx-auto max-w-5xl">
            <header className="mx-auto mb-12 max-w-2xl text-center md:mb-16">
              <h2
                id="pricing-heading"
                className="text-3xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl"
              >
                Take Your Trading to the{" "}
                <span className={LANDING_TITLE_GRADIENT}>Next Level</span>
              </h2>
              <p className="mt-4 text-lg leading-relaxed text-gray-400 md:text-xl">
                Stop guessing. Start tracking, analyzing, and improving with real data.
              </p>
              <p className="mt-4 text-sm text-gray-500">
                Trusted by growing traders every day
              </p>
            </header>

            <div className="grid gap-8 lg:grid-cols-2 lg:gap-10 lg:items-stretch">
              <div className="flex h-full flex-col rounded-2xl border border-white/10 bg-white/[0.04] p-8 shadow-lg shadow-black/25 backdrop-blur-md md:p-9">
                <div className="flex min-h-[7.25rem] flex-col text-left md:min-h-[7rem] lg:min-h-[6.75rem]">
                  <h3 className="text-xl font-semibold text-gray-100">Free</h3>
                  <p className="mt-2 text-4xl font-bold tracking-tight text-white">$0</p>
                  <p className="mt-3 flex-1 text-sm leading-relaxed text-gray-400">
                    Everything you need to start tracking and sharing your trades.
                  </p>
                </div>
                <ul className="mt-8 flex flex-1 flex-col gap-3 text-left text-sm text-gray-300">
                  {PRICING_FREE_FEATURES.map((line) => (
                    <li key={line} className="flex gap-3">
                      <span className="mt-0.5 shrink-0 text-emerald-400/90" aria-hidden>
                        ✓
                      </span>
                      <span className="leading-snug">{line}</span>
                    </li>
                  ))}
                </ul>
                <button
                  type="button"
                  onClick={() => router.push("/login")}
                  className="mt-10 w-full rounded-xl border border-white/15 bg-white/[0.06] px-6 py-3.5 font-semibold text-white transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:border-emerald-400/25 hover:bg-white/[0.10] hover:shadow-[0_0_24px_rgba(52,211,153,0.12)] motion-reduce:hover:scale-100"
                >
                  Start Free
                </button>
              </div>

              <div className="relative flex h-full flex-col lg:-translate-y-1 lg:justify-center">
                <div className="pointer-events-none absolute left-1/2 top-2 z-10 -translate-x-1/2 lg:-top-1">
                  <span className="inline-flex rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 px-4 py-1.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-white shadow-lg shadow-emerald-500/30">
                    MOST POPULAR
                  </span>
                </div>
                <div className="flex h-full flex-col rounded-2xl border border-emerald-400/45 bg-gradient-to-b from-white/[0.1] to-emerald-950/30 p-8 pb-9 pt-12 shadow-[0_8px_48px_rgba(0,0,0,0.35),0_0_52px_rgba(52,211,153,0.2)] backdrop-blur-md transition-[transform,box-shadow] duration-300 ease-out hover:z-[1] hover:scale-[1.02] hover:border-emerald-400/60 hover:shadow-[0_12px_56px_rgba(0,0,0,0.4),0_0_64px_rgba(52,211,153,0.32)] motion-reduce:transition-none motion-reduce:hover:scale-100 md:p-10 md:pb-10 md:pt-14">
                  <div className="flex min-h-[7.25rem] flex-col text-left md:min-h-[7rem] lg:min-h-[6.75rem]">
                    <h3 className="text-xl font-semibold text-emerald-200">TraxPro</h3>
                    <p className="mt-2 text-4xl font-bold tracking-tight text-white md:text-[2.35rem]">
                      $16.99
                      <span className="text-lg font-semibold text-gray-400">/month</span>
                    </p>
                    <p className="mt-3 flex-1 text-sm leading-relaxed text-gray-200">
                      Unlock full analytics, deeper insights, and unlimited access.
                    </p>
                  </div>
                  <ul className="mt-8 flex flex-1 flex-col gap-3 text-left text-sm text-gray-100">
                    {PRICING_PRO_FEATURES.map((line) => (
                      <li key={line} className="flex gap-3">
                        <span className="mt-0.5 shrink-0 text-emerald-400" aria-hidden>
                          ✓
                        </span>
                        <span className="leading-snug">{line}</span>
                      </li>
                    ))}
                  </ul>
                  <button
                    type="button"
                    disabled={checkoutLoading}
                    onClick={() => void handleSubscribe()}
                    className="mt-10 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 px-6 py-3.5 font-semibold text-white shadow-lg shadow-emerald-500/20 transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:from-blue-600 hover:to-emerald-600 hover:shadow-[0_0_28px_rgba(52,211,153,0.35)] disabled:cursor-not-allowed disabled:opacity-60 motion-reduce:hover:scale-100"
                  >
                    {checkoutLoading ? "Starting trial..." : "Start Free Trial"}
                  </button>
                  <p className="mt-4 text-center text-xs leading-relaxed text-gray-500">
                    ✓ 14-day free trial ✓ Cancel anytime ✓ No commitment
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <LandingFinalCtaSection
          checkoutLoading={checkoutLoading}
          onStartTrial={() => void handleSubscribe()}
          onPreview={() => router.push("/app")}
        />

        <footer className="border-t border-white/10 py-10">
          <div className="mx-auto max-w-4xl px-6">
            <p className="text-center text-sm text-gray-500">
              Built for traders who actually want to improve.
            </p>
            <nav
              aria-label="Legal and resources"
              className="mt-6 flex flex-col items-center gap-3 sm:flex-row sm:flex-wrap sm:justify-center sm:gap-x-6 sm:gap-y-2"
            >
              <Link
                href="/privacy"
                className="text-sm text-gray-400 transition hover:text-gray-300"
              >
                Privacy Policy
              </Link>
              <Link
                href="/terms"
                className="text-sm text-gray-400 transition hover:text-gray-300"
              >
                Terms of Service
              </Link>
              <a
                href={`mailto:${LEGAL_CONTACT_EMAIL}`}
                className="text-sm text-gray-400 transition hover:text-gray-300"
              >
                Contact Support
              </a>
            </nav>
          </div>
        </footer>
        </div>
      </div>
    </>
  )
}
