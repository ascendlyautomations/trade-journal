"use client"

import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  useLandingReveal,
} from "@/lib/landingPageUi"

const DISCONNECTED_PLATFORMS = [
  { icon: "💬", label: "Discord" },
  { icon: "📊", label: "Journal Apps" },
  { icon: "📱", label: "Social Media" },
  { icon: "📈", label: "Prop Firms" },
  { icon: "📑", label: "Spreadsheets" },
  { icon: "📝", label: "Notes" },
] as const

export default function LandingProblemSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="problem"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="problem-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div
          className={`mx-auto max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <h2 id="problem-heading" className={LANDING_HEADLINE_SM}>
            Trading has never had a true home.
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-5`}>
            Traders bounce between journals, charts, social medias, and spreadsheets - with no single
            place to learn, share, and grow.
          </p>
        </div>

        <div
          className={`mx-auto mt-14 max-w-3xl ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-100 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <div className={`${LANDING_CARD_FULL} p-8 md:p-10`}>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {DISCONNECTED_PLATFORMS.map((platform) => (
                <div
                  key={platform.label}
                  className="flex flex-col items-center gap-2 rounded-xl border border-white/[0.06] bg-white/[0.02] px-3 py-5 text-center"
                >
                  <span className="text-2xl" aria-hidden>
                    {platform.icon}
                  </span>
                  <span className="text-sm text-gray-400">{platform.label}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="flex justify-center py-6 text-gray-600" aria-hidden>
            <span className="text-3xl">↓</span>
          </div>

          <div
            className={`${LANDING_CARD_FULL} border-emerald-400/20 bg-emerald-500/[0.04] p-8 text-center md:p-10`}
          >
            <p className="text-3xl font-medium uppercase tracking-widest text-emerald-400/80">
              TradeTraxs
            </p>
            <h3 className="mt-2 text-sm text-white md:text-xl">
              One connected home for traders.
            </h3>
          </div>
        </div>
      </div>
    </section>
  )
}
