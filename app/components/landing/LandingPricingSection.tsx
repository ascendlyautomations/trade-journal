"use client"

import { useState } from "react"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
  TRADETRAXS_PRO_FEATURES_HEADING,
} from "@/lib/tradeTraxsPlans"
import {
  TRAXPRO_CHECKOUT_FINE_PRINT,
  TRAXPRO_TRIAL_HEADLINE,
} from "@/lib/traxProPricing"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import { setCheckoutBillingInterval } from "@/lib/signupFlow"
import TraxProBillingIntervalPicker from "@/app/components/TraxProBillingIntervalPicker"
import TraxProSelectedPlanPrice from "@/app/components/TraxProSelectedPlanPrice"
import {
  LANDING_HEADLINE_SM,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  LANDING_TITLE_GRADIENT,
} from "@/lib/landingPageUi"
import {
  PRICING_CARD_FEATURE_ITEM,
  PRICING_CARD_FEATURE_LIST,
  PRICING_CARD_FEATURE_TEXT,
  PRICING_CARD_PLAN_DESCRIPTION,
  PRICING_CARD_PRO_FEATURE_LIST,
  PRICING_CARD_PRO_FEATURES_HEADING,
  PRICING_CARD_PRO_PLAN_DESCRIPTION,
} from "@/lib/pricingPlanCardUi"

type Props = {
  checkoutLoading: boolean
  onStartTrial: (billingInterval: TraxProBillingIntervalId) => void
  onStartFree: () => void
  showMarketingCTAs?: boolean
}

export default function LandingPricingSection({
  checkoutLoading,
  onStartTrial,
  onStartFree,
  showMarketingCTAs = true,
}: Props) {
  const [billingInterval, setBillingInterval] = useState<TraxProBillingIntervalId>(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )

  function handleIntervalChange(interval: TraxProBillingIntervalId) {
    setBillingInterval(interval)
    setCheckoutBillingInterval(interval)
  }

  return (
    <section
      id="pricing"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="pricing-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <header className="mx-auto mb-12 max-w-2xl text-center md:mb-16">
          <h2 id="pricing-heading" className={`${LANDING_HEADLINE_SM}`}>
            Start Free.{" "}
            <span className={LANDING_TITLE_GRADIENT}>Upgrade When You&apos;re Ready.</span>
          </h2>
        </header>

        <div className="mx-auto grid max-w-5xl gap-8 lg:grid-cols-2 lg:items-start lg:gap-10">
          <div className="flex w-full flex-col self-start rounded-2xl border border-white/10 bg-white/[0.04] p-8 shadow-lg shadow-black/25 backdrop-blur-md md:p-9">
            <h3 className="text-xl font-semibold text-gray-100">{TRADETRAXS_FREE_PLAN.name}</h3>
            <p className="mt-2 text-4xl font-bold tracking-tight text-white">$0</p>
            <p className={PRICING_CARD_PLAN_DESCRIPTION}>
              {TRADETRAXS_FREE_PLAN.description}
            </p>
            <ul className={`${PRICING_CARD_FEATURE_LIST} grow-0`}>
              {TRADETRAXS_FREE_PLAN.features.map((line) => (
                <li key={line} className={PRICING_CARD_FEATURE_ITEM}>
                  <span className="mt-0.5 shrink-0 text-emerald-400/90" aria-hidden>
                    ✓
                  </span>
                  <span className={PRICING_CARD_FEATURE_TEXT}>{line}</span>
                </li>
              ))}
            </ul>
            {showMarketingCTAs ? (
              <button
                type="button"
                onClick={onStartFree}
                className="mt-3 w-full rounded-xl border border-white/15 bg-white/[0.06] px-6 py-3.5 font-semibold text-white transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:border-emerald-400/25 hover:bg-white/[0.10] hover:shadow-[0_0_24px_rgba(52,211,153,0.12)] motion-reduce:hover:scale-100"
              >
                Start Free
              </button>
            ) : null}
          </div>

          <div className="relative flex h-full flex-col lg:-translate-y-1 lg:justify-center">
            <div className="pointer-events-none absolute left-1/2 top-2 z-10 -translate-x-1/2 lg:-top-1">
              <span className="inline-flex rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 px-4 py-1.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-white shadow-lg shadow-emerald-500/30">
                Most Popular
              </span>
            </div>
            <div className="flex h-full flex-col rounded-2xl border border-emerald-400/45 bg-gradient-to-b from-white/[0.1] to-emerald-950/30 p-8 pb-9 pt-12 shadow-[0_8px_48px_rgba(0,0,0,0.35),0_0_52px_rgba(52,211,153,0.2)] backdrop-blur-md transition-[transform,box-shadow] duration-300 ease-out hover:z-[1] hover:scale-[1.02] hover:border-emerald-400/60 hover:shadow-[0_12px_56px_rgba(0,0,0,0.4),0_0_64px_rgba(52,211,153,0.32)] motion-reduce:transition-none motion-reduce:hover:scale-100 md:p-10 md:pb-10 md:pt-14">
              <h3 className="text-xl font-semibold text-emerald-200">{TRADETRAXS_PRO_PLAN.name}</h3>
              <p className="mt-2 text-sm font-semibold uppercase tracking-wide text-emerald-300/90">
                {TRAXPRO_TRIAL_HEADLINE}
              </p>
              <TraxProSelectedPlanPrice
                interval={billingInterval}
                variant="full"
                className="mt-2 text-white"
              />
              <p className={PRICING_CARD_PRO_PLAN_DESCRIPTION}>
                {TRADETRAXS_PRO_PLAN.description}
              </p>
              <p className={PRICING_CARD_PRO_FEATURES_HEADING}>
                {TRADETRAXS_PRO_FEATURES_HEADING}
              </p>
              <ul className={PRICING_CARD_PRO_FEATURE_LIST}>
                {TRADETRAXS_PRO_PLAN.features.map((line) => (
                  <li key={line} className={PRICING_CARD_FEATURE_ITEM}>
                    <span className="mt-0.5 shrink-0 text-emerald-400" aria-hidden>
                      ✓
                    </span>
                    <span className={PRICING_CARD_FEATURE_TEXT}>{line}</span>
                  </li>
                ))}
              </ul>
              {showMarketingCTAs ? (
                <>
                  <div className="mt-6">
                    <TraxProBillingIntervalPicker
                      value={billingInterval}
                      onChange={handleIntervalChange}
                      disabled={checkoutLoading}
                    />
                  </div>
                  <button
                    type="button"
                    disabled={checkoutLoading}
                    onClick={() => onStartTrial(billingInterval)}
                    className="mt-6 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 px-6 py-3.5 font-semibold text-white shadow-lg shadow-emerald-500/20 transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:from-blue-600 hover:to-emerald-600 hover:shadow-[0_0_28px_rgba(52,211,153,0.35)] disabled:cursor-not-allowed disabled:opacity-60 motion-reduce:hover:scale-100"
                  >
                    {checkoutLoading ? "Starting trial…" : `Start ${TRAXPRO_TRIAL_HEADLINE}!`}
                  </button>
                  <p className="mt-4 text-center text-xs leading-relaxed text-gray-500">
                    {TRAXPRO_CHECKOUT_FINE_PRINT}
                  </p>
                </>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
