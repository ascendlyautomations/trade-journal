"use client"

import { LANDING_BRAND_TAGLINE } from "@/lib/landingFlagships"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"

type Props = {
  checkoutLoading: boolean
  onStartTrial: () => void
}

export default function LandingFinalCtaSection({ checkoutLoading, onStartTrial }: Props) {
  return (
    <section
      className="relative z-10 mx-auto max-w-4xl border-t border-white/10 px-6 py-24 text-center"
      aria-labelledby="final-cta-heading"
    >
      <div className="rounded-2xl border border-white/10 bg-gradient-to-br from-white/[0.07] via-white/[0.04] to-emerald-500/[0.06] px-6 py-12 shadow-lg shadow-black/25 backdrop-blur-md md:px-10 md:py-14">
        <h2 id="final-cta-heading" className="mb-4 text-3xl font-extrabold tracking-tight text-white md:text-4xl">
          {LANDING_BRAND_TAGLINE}
        </h2>
        <p className="mx-auto mb-10 max-w-lg text-base leading-relaxed text-gray-400 md:text-lg">
          Join TradeTraxs to track your trades, connect with other traders, sharpen your edge, and
          grow together.
        </p>
        <button
          type="button"
          disabled={checkoutLoading}
          onClick={onStartTrial}
          className="min-w-[220px] rounded-xl bg-emerald-500 px-8 py-3.5 text-base font-semibold text-white hover:bg-emerald-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {checkoutLoading ? "Starting trial…" : `Start ${TRAXPRO_TRIAL_HEADLINE}!`}
        </button>
      </div>
    </section>
  )
}
