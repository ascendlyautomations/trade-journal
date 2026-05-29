"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useState } from "react"
import PublicNavbar from "../components/PublicNavbar"
import { supabase } from "@/lib/supabaseClient"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

const freeFeatures = [
  "Track your trades",
  "1 trading account",
  "Basic trade history",
  "Limited dashboard insights",
]

const proFeatures = [
  "Unlimited trading accounts",
  "Full performance dashboard",
  "AI Trade Analyst (automated insights)",
  "Advanced analytics & stats",
  "Session + strategy breakdowns",
  "Track what actually makes you money",
]

const whyTraxPro = [
  "See your real win rate",
  "Identify what setups work",
  "Eliminate bad trades",
  "Improve faster with AI feedback",
]

function CheckIcon({ bright = false }: { bright?: boolean }) {
  return (
    <svg
      className={`mt-0.5 h-5 w-5 shrink-0 ${bright ? "text-teal-300" : "text-teal-400/70"}`}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={2}
      aria-hidden
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
    </svg>
  )
}

export default function PricingPage() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const [checkoutLoading, setCheckoutLoading] = useState(false)

  async function handleTraxProCheckout() {
    setCheckoutLoading(true)
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        showPopup({ type: "info", message: "Please log in first" })
        return
      }

      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId: user.id,
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
        showPopup({ type: "error", message: data.error || "Checkout failed" })
      }
    } catch (e) {
      console.error("Checkout error:", e)
      showPopup({ type: "error", message: "Checkout failed" })
    } finally {
      setCheckoutLoading(false)
    }
  }

  return (
    <>
      <PublicNavbar />
      <FeedbackModal {...feedbackModalProps} />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-14 text-white sm:px-6 sm:py-20">
        <div className="mx-auto flex max-w-5xl flex-col items-center">
          {/* Top section */}
          <h1 className="max-w-3xl text-center text-3xl font-bold leading-tight tracking-tight sm:text-4xl md:text-5xl">
            Take Your Trading to the Next Level
          </h1>
          <p className="mt-4 max-w-2xl text-center text-base text-gray-200 sm:text-lg md:text-xl">
            Stop guessing. Start tracking, analyzing, and improving with real
            data.
          </p>
          <p className="mt-6 text-center text-sm font-medium text-teal-300/90 sm:text-base">
            Trusted by growing traders every day
          </p>

          <div className="mt-14 grid w-full max-w-4xl gap-8 md:grid-cols-2 md:items-center md:gap-10">
            {/* Free — secondary emphasis */}
            <div className="order-2 flex flex-col rounded-2xl border border-white/10 bg-white/[0.06] p-8 opacity-90 shadow-lg backdrop-blur-md md:order-1">
              <h2 className="text-lg font-semibold text-gray-200">Free</h2>
              <p className="mt-2 text-3xl font-bold tracking-tight text-gray-100">
                $0
              </p>
              <p className="mt-3 text-sm leading-relaxed text-gray-400">
                Perfect for getting started with trade tracking.
              </p>

              <ul className="mt-8 flex flex-1 flex-col gap-3 text-sm text-gray-400">
                {freeFeatures.map((f) => (
                  <li key={f} className="flex gap-3">
                    <CheckIcon />
                    <span>{f}</span>
                  </li>
                ))}
              </ul>

              <button
                type="button"
                onClick={() => router.push("/login")}
                className="mt-8 w-full rounded-xl bg-white py-3 text-center text-sm font-semibold text-black transition hover:bg-gray-100"
              >
                Start Free
              </button>
            </div>

            {/* TraxPro — dominant */}
            <div className="relative z-10 order-1 flex flex-col rounded-2xl border-2 border-blue-500 bg-white/10 p-6 shadow-lg backdrop-blur-md scale-105 max-md:scale-100 md:shadow-2xl">
              <span className="absolute -top-3 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-gradient-to-r from-blue-500 to-teal-400 px-4 py-1.5 text-xs font-bold uppercase tracking-wide text-white shadow-lg">
                🔥 Most Popular
              </span>

              <h2 className="mt-0 text-xl font-bold text-white">TraxPro</h2>
              <p className="mt-2 text-4xl font-bold tracking-tight sm:text-5xl">
                $16.99
                <span className="text-lg font-semibold text-gray-200 sm:text-xl">
                  /month
                </span>
              </p>
              <p className="mt-3 text-sm leading-relaxed text-gray-200 sm:text-base">
                Everything you need to become a consistently profitable trader.
              </p>

              <ul className="mt-4 flex flex-1 flex-col gap-3.5 text-sm text-gray-100 sm:text-[0.95rem]">
                {proFeatures.map((f) => (
                  <li key={f} className="flex gap-3">
                    <CheckIcon bright />
                    <span>{f}</span>
                  </li>
                ))}
              </ul>

              <button
                type="button"
                disabled={checkoutLoading}
                onClick={handleTraxProCheckout}
                className="mt-5 w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-4 text-center text-base font-bold text-white shadow-lg transition hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60 sm:py-[1.125rem] sm:text-lg"
              >
                {checkoutLoading ? "Loading…" : "Start Free Trial"}
              </button>
              <div className="mt-4 space-y-1.5 text-center text-xs text-gray-300 sm:text-sm">
                <p>✔ 14-day free trial   ✔ Cancel anytime   ✔ No commitment</p>
                
              </div>
            </div>
          </div>

          <p className="mt-14 max-w-lg text-center text-sm italic text-gray-400 sm:text-base">
            Most traders upgrade within their first week after seeing their
            data.
          </p>

          {/* Why TraxPro */}
          <section
            className="mt-16 w-full max-w-2xl rounded-2xl border border-white/10 bg-white/5 p-8 backdrop-blur-sm sm:p-10"
            aria-labelledby="why-traxpro-heading"
          >
            <h2
              id="why-traxpro-heading"
              className="text-center text-xl font-bold text-white sm:text-2xl"
            >
              Why TraxPro?
            </h2>
            <ul className="mt-8 flex flex-col gap-4 text-left text-sm text-gray-200 sm:text-base">
              {whyTraxPro.map((line) => (
                <li key={line} className="flex gap-3">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-teal-400" />
                  <span>{line}</span>
                </li>
              ))}
            </ul>
          </section>

          <p className="mt-12 text-sm text-gray-500">
            <Link href="/" className="text-blue-400 hover:underline">
              ← Back to home
            </Link>
          </p>
        </div>
      </div>
    </>
  )
}
