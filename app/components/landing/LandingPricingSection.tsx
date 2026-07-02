"use client"

import {
  LANDING_FREE_FEATURES,
  LANDING_PRO_PRICING_HIGHLIGHTS,
  TRAXPRO_BILLING_LABEL,
  TRAXPRO_CHECKOUT_FINE_PRINT,
  TRAXPRO_PLAN_NAME,
  TRAXPRO_PRICE_DISPLAY,
  TRAXPRO_TRIAL_HEADLINE,
} from "@/lib/traxProPricing"
import {
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  LANDING_TITLE_GRADIENT,
} from "@/lib/landingPageUi"

type Props = {
  checkoutLoading: boolean
  onStartTrial: () => void
  onStartFree: () => void
}

export default function LandingPricingSection({
  checkoutLoading,
  onStartTrial,
  onStartFree,
}: Props) {
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

        <div className="mx-auto grid max-w-5xl gap-8 lg:grid-cols-2 lg:items-stretch lg:gap-10">
          <div className="flex h-full flex-col rounded-2xl border border-white/10 bg-white/[0.04] p-8 shadow-lg shadow-black/25 backdrop-blur-md md:p-9">
            <h3 className="text-xl font-semibold text-gray-100">Free</h3>
            <p className="mt-2 text-4xl font-bold tracking-tight text-white">$0</p>
            <p className="mt-3 text-sm leading-relaxed text-gray-400">
              Explore the trader home.
            </p>
            <ul className="mt-8 flex flex-1 flex-col gap-3 text-left text-sm text-gray-300">
              {LANDING_FREE_FEATURES.map((line) => (
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
              onClick={onStartFree}
              className="mt-10 w-full rounded-xl border border-white/15 bg-white/[0.06] px-6 py-3.5 font-semibold text-white transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:border-emerald-400/25 hover:bg-white/[0.10] hover:shadow-[0_0_24px_rgba(52,211,153,0.12)] motion-reduce:hover:scale-100"
            >
              Start Free
            </button>
          </div>

          <div className="relative flex h-full flex-col lg:-translate-y-1 lg:justify-center">
            <div className="pointer-events-none absolute left-1/2 top-2 z-10 -translate-x-1/2 lg:-top-1">
              <span className="inline-flex rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 px-4 py-1.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-white shadow-lg shadow-emerald-500/30">
                Most Popular
              </span>
            </div>
            <div className="flex h-full flex-col rounded-2xl border border-emerald-400/45 bg-gradient-to-b from-white/[0.1] to-emerald-950/30 p-8 pb-9 pt-12 shadow-[0_8px_48px_rgba(0,0,0,0.35),0_0_52px_rgba(52,211,153,0.2)] backdrop-blur-md transition-[transform,box-shadow] duration-300 ease-out hover:z-[1] hover:scale-[1.02] hover:border-emerald-400/60 hover:shadow-[0_12px_56px_rgba(0,0,0,0.4),0_0_64px_rgba(52,211,153,0.32)] motion-reduce:transition-none motion-reduce:hover:scale-100 md:p-10 md:pb-10 md:pt-14">
              <h3 className="text-xl font-semibold text-emerald-200">{TRAXPRO_PLAN_NAME}</h3>
              <p className="mt-2 text-sm font-semibold uppercase tracking-wide text-emerald-300/90">
                {TRAXPRO_TRIAL_HEADLINE}
              </p>
              <p className="mt-2 text-4xl font-bold tracking-tight text-white md:text-[2.35rem]">
                {TRAXPRO_PRICE_DISPLAY}
              </p>
              <p className="mt-1 text-sm font-medium text-gray-400">{TRAXPRO_BILLING_LABEL}</p>
              <ul className="mt-8 flex flex-1 flex-col gap-3 text-left text-sm text-gray-100">
                {LANDING_PRO_PRICING_HIGHLIGHTS.map((line) => (
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
                onClick={onStartTrial}
                className="mt-10 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 px-6 py-3.5 font-semibold text-white shadow-lg shadow-emerald-500/20 transition-[transform,box-shadow] duration-200 hover:scale-[1.02] hover:from-blue-600 hover:to-emerald-600 hover:shadow-[0_0_28px_rgba(52,211,153,0.35)] disabled:cursor-not-allowed disabled:opacity-60 motion-reduce:hover:scale-100"
              >
                {checkoutLoading ? "Starting trial…" : "Start Free Trial"}
              </button>
              <p className="mt-4 text-center text-xs leading-relaxed text-gray-500">
                {TRAXPRO_CHECKOUT_FINE_PRINT}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
