"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { enterSignupFlow, setCheckoutBillingInterval } from "@/lib/signupFlow"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets } from "@/lib/feedbackPresets"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
  TRADETRAXS_PRO_FEATURES_HEADING,
} from "@/lib/tradeTraxsPlans"
import {
  TRAXPRO_CHECKOUT_FINE_PRINT,
  TRAXPRO_PRICE_STARTING_AT,
  TRAXPRO_TRIAL_HEADLINE,
} from "@/lib/traxProPricing"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import TraxProBillingIntervalPicker from "@/app/components/TraxProBillingIntervalPicker"
import TraxProSelectedPlanPrice from "@/app/components/TraxProSelectedPlanPrice"
import {
  PRICING_CARD_FEATURE_ITEM,
  PRICING_CARD_FEATURE_LIST,
  PRICING_CARD_PLAN_DESCRIPTION,
  PRICING_CARD_PRO_FEATURE_LIST,
  PRICING_CARD_PRO_FEATURES_HEADING_ALT,
  PRICING_CARD_PRO_PLAN_DESCRIPTION_LIGHT,
  PRICING_PAGE_CTA_FINE_PRINT,
  PRICING_PAGE_PRIMARY_CTA,
  PRICING_PAGE_WHY_PRO_BULLETS,
  PRICING_PAGE_WHY_PRO_ITEM,
  PRICING_PAGE_WHY_PRO_LIST,
} from "@/lib/pricingPlanCardUi"

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
  const [billingInterval, setBillingInterval] = useState<TraxProBillingIntervalId>(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )

  function handleIntervalChange(interval: TraxProBillingIntervalId) {
    setBillingInterval(interval)
    setCheckoutBillingInterval(interval)
  }

  async function handleTraxProCheckout() {
    setCheckoutLoading(true)
    setCheckoutBillingInterval(billingInterval)
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        enterSignupFlow()
        setCheckoutLoading(false)
        router.push("/login?tab=signup")
        return
      }

      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId: user.id,
          billingInterval,
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
    } catch (e) {
      console.error("Checkout error:", e)
      showPopup(feedbackPresets.subscriptionCheckoutFailed("Checkout failed"))
    } finally {
      setCheckoutLoading(false)
    }
  }

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-14 text-white sm:px-6 sm:py-20">
        <div className="mx-auto flex max-w-5xl flex-col items-center">
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

          <div className="mt-14 grid w-full max-w-4xl gap-8 md:grid-cols-2 md:items-start md:gap-10">
            <div className="order-2 flex w-full flex-col self-start rounded-2xl border border-white/10 bg-white/[0.06] px-8 pt-8 pb-6 opacity-90 shadow-lg backdrop-blur-md md:order-1">
              <h2 className="text-lg font-semibold text-gray-200">{TRADETRAXS_FREE_PLAN.name}</h2>
              <p className="mt-2 text-3xl font-bold tracking-tight text-gray-100">
                $0
              </p>
              <p className={PRICING_CARD_PLAN_DESCRIPTION}>
                {TRADETRAXS_FREE_PLAN.description}
              </p>

              <ul className={`${PRICING_CARD_FEATURE_LIST} grow-0 text-gray-400`}>
                {TRADETRAXS_FREE_PLAN.features.map((f) => (
                  <li key={f} className={PRICING_CARD_FEATURE_ITEM}>
                    <CheckIcon />
                    <span>{f}</span>
                  </li>
                ))}
              </ul>

              <button
                type="button"
                onClick={() => router.push("/login")}
                className="mt-3 w-full rounded-xl bg-white py-3 text-center text-sm font-semibold text-black transition hover:bg-gray-100"
              >
                Start Free
              </button>
            </div>

            <div className="relative z-10 order-1 flex flex-col rounded-2xl border-2 border-blue-500 bg-white/10 p-6 shadow-lg backdrop-blur-md scale-105 max-md:scale-100 md:shadow-2xl">
              <span className="absolute -top-3 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-gradient-to-r from-blue-500 to-teal-400 px-4 py-1.5 text-xs font-bold uppercase tracking-wide text-white shadow-lg">
                🔥 Most Popular
              </span>

              <h2 className="mt-0 text-xl font-bold text-white">{TRADETRAXS_PRO_PLAN.name}</h2>
              <TraxProSelectedPlanPrice interval={billingInterval} variant="full" className="text-white" />
              <p className="mt-1 text-xs text-gray-400">{TRAXPRO_PRICE_STARTING_AT}</p>
              <p className={PRICING_CARD_PRO_PLAN_DESCRIPTION_LIGHT}>
                {TRADETRAXS_PRO_PLAN.description}
              </p>

              <p className={PRICING_CARD_PRO_FEATURES_HEADING_ALT}>
                {TRADETRAXS_PRO_FEATURES_HEADING}
              </p>
              <ul className={PRICING_CARD_PRO_FEATURE_LIST}>
                {TRADETRAXS_PRO_PLAN.features.map((f) => (
                  <li key={f} className={PRICING_CARD_FEATURE_ITEM}>
                    <CheckIcon bright />
                    <span>{f}</span>
                  </li>
                ))}
              </ul>

              <div className="mt-4">
                <TraxProBillingIntervalPicker
                  value={billingInterval}
                  onChange={handleIntervalChange}
                  disabled={checkoutLoading}
                />
              </div>

              <button
                type="button"
                disabled={checkoutLoading}
                onClick={handleTraxProCheckout}
                className={PRICING_PAGE_PRIMARY_CTA}
              >
                {checkoutLoading ? "Loading…" : `Start ${TRAXPRO_TRIAL_HEADLINE}`}
              </button>
              <div className={PRICING_PAGE_CTA_FINE_PRINT}>
                <p>{TRAXPRO_CHECKOUT_FINE_PRINT}</p>
              </div>
            </div>
          </div>

          <p className="mt-12 max-w-lg text-center text-sm italic text-gray-400 sm:text-base">
            Most traders upgrade within their first week after seeing their
            data.
          </p>

          <section
            className="mt-12 w-full max-w-3xl rounded-2xl border border-white/10 bg-white/5 p-8 backdrop-blur-sm sm:p-10"
            aria-labelledby="why-traxpro-heading"
          >
            <h2
              id="why-traxpro-heading"
              className="text-center text-xl font-bold text-white sm:text-2xl"
            >
              Why {TRADETRAXS_PRO_PLAN.name}?
            </h2>
            <ul className={PRICING_PAGE_WHY_PRO_LIST}>
              {PRICING_PAGE_WHY_PRO_BULLETS.map((line) => (
                <li key={line} className={PRICING_PAGE_WHY_PRO_ITEM}>
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
