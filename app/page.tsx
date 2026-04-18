"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import PublicNavbar from "./components/PublicNavbar"
import LandingComparisonSection from "./components/LandingComparisonSection"
import LandingFeatureShowcaseSections from "./components/LandingFeatureShowcaseSections"
import LandingCommunitySection from "./components/LandingCommunitySection"
import LandingTradingContentSection from "./components/LandingTradingContentSection"
import LandingFeatureGridSection from "./components/LandingFeatureGridSection"
import LandingFinalCtaSection from "./components/LandingFinalCtaSection"
import AIAssistant from "@/app/components/AIAssistant"
import { supabase } from "../lib/supabaseClient"
import {
  LANDING_CARD_FULL,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"

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

export default function LandingPage() {
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
      alert("Checkout failed. Please try again.")
    } finally {
      setCheckoutLoading(false)
    }
  }

  return (
    <>
      <PublicNavbar />
      <AIAssistant />

      {/* 🔥 NEW BLUE → GREEN THEME */}
      <div className="relative min-h-screen text-gray-100 overflow-hidden">
        {/* 🔥 BACKGROUND IMAGE */}
        <div className="absolute inset-0">
          <img
            src="/hero.png"
            className="w-full h-full object-cover opacity-40"
            style={{ objectPosition: "15% center" }}
            alt=""
          />
        </div>
        {/* 🔥 DARK OVERLAY */}
        <div className="absolute inset-0 bg-gradient-to-br from-[#0f172a]/60 via-[#1e293b]/60 to-[#065f46]/60" />

        {/* HERO */}
        <div className="relative z-10 flex flex-col items-center text-center px-6 pt-32 pb-14 md:pb-20">
          {/* 🔥 GLOW */}
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
        </div>

        {/* HOW IT WORKS */}
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

        {/* PRICING */}
        <div id="pricing" className="py-24 px-6 text-center border-t border-white/10">
          <h2 className="text-4xl font-extrabold mb-4 text-white tracking-tight drop-shadow-lg">
            Pricing
          </h2>
          <p className="text-gray-400 text-sm mb-10 max-w-md mx-auto">
            Start free. Upgrade when you&apos;re ready to go deeper.
          </p>

          <div className="flex justify-center">
            <div className="bg-white/5 border border-white/10 backdrop-blur-md p-8 rounded-xl w-80">
              <h3 className="text-xl font-semibold mb-4">Starter</h3>
              <p className="text-4xl font-bold mb-4">$0</p>
              <p className="text-gray-400 text-sm mb-6 leading-relaxed">
                Core journaling and exploration—no card required.
              </p>
              <button
                type="button"
                onClick={() => router.push("/login")}
                className="bg-emerald-500 hover:bg-emerald-600 px-6 py-3 rounded-lg w-full"
              >
                Get Started
              </button>
            </div>
          </div>
        </div>

        <LandingFinalCtaSection
          checkoutLoading={checkoutLoading}
          onStartTrial={() => void handleSubscribe()}
          onPreview={() => router.push("/app")}
        />

        {/* FOOTER */}
        <div className="text-center text-gray-500 text-sm py-10 border-t border-white/10">
          Built for traders who actually want to improve.
        </div>
      </div>
    </>
  )
}
