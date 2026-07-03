"use client"

import {
  LANDING_EYEBROW,
  LANDING_HEADLINE,
  LANDING_PRIMARY_BUTTON,
  LANDING_SECONDARY_BUTTON,
  LANDING_SECTION_SHELL,
} from "@/lib/landingPageUi"
import { TRAXPRO_TRIAL_HEADLINE, TRAXPRO_PLAN_NAME } from "@/lib/traxProPricing"

type Props = {
  checkoutLoading: boolean
  onStartTrial: () => void
  onExplore: () => void
}

export default function LandingHeroSection({
  checkoutLoading,
  onStartTrial,
  onExplore,
}: Props) {
  return (
    <section className="relative overflow-hidden pt-28 pb-24 md:pt-36 md:pb-32 lg:pb-40">
      <div className={`${LANDING_SECTION_SHELL} relative`}>
        <div className="mx-auto max-w-4xl text-center">
          <p className={LANDING_EYEBROW}>TradeTraxs</p>
          <h1 className={`${LANDING_HEADLINE} mt-6`}>
            The First Social Platform
            <span className="mt-2 block text-blue-400">Built for Traders.</span>
          </h1>

          <p className="mx-auto mt-6 max-w-xl text-lg text-zinc-400 md:text-xl">
            Six flagship experiences. One connected ecosystem.
          </p>

          <div className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row sm:gap-4">
            <button
              type="button"
              disabled={checkoutLoading}
              onClick={onStartTrial}
              className={`${LANDING_PRIMARY_BUTTON} min-w-[220px] px-8`}
            >
              {checkoutLoading ? "Starting trial…" : `Start ${TRAXPRO_TRIAL_HEADLINE}`}
            </button>
            <button
              type="button"
              onClick={onExplore}
              className={`${LANDING_SECONDARY_BUTTON} min-w-[220px] px-8`}
            >
              Explore TradeTraxs
            </button>
          </div>
          <p className="mt-4 text-sm text-zinc-500">{TRAXPRO_TRIAL_HEADLINE} on {TRAXPRO_PLAN_NAME}</p>
        </div>
      </div>
    </section>
  )
}
