"use client"

import Image from "next/image"
import {
  LANDING_EYEBROW,
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

export default function LandingAnalyticsSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="analytics"
      className={`relative ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="analytics-heading"
    >
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 70% 45% at 50% 40%, rgba(59, 130, 246, 0.035) 0%, transparent 72%)",
        }}
        aria-hidden
      />
      <div className={`${LANDING_SECTION_SHELL} relative`}>
        <div
          className={`mx-auto max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className={LANDING_EYEBROW}>Analytics</p>
          <h2 id="analytics-heading" className={`${LANDING_HEADLINE_SM} mt-4`}>
            Know your edge.
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-5`}>
            See what&apos;s working and trade with more confidence.
          </p>
        </div>

        <div
          className={`mx-auto mt-14 max-w-5xl space-y-5 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-75 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <div className="overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-2 shadow-2xl shadow-black/50">
            <div className="relative aspect-[16/9] w-full overflow-hidden rounded-xl md:aspect-[2/1]">
              <Image
                src="/images/dashboard.webp"
                alt="TradeTraxs analytics dashboard with win rate and session data"
                fill
                className="object-cover object-top"
                sizes="(max-width: 1024px) 100vw, 960px"
                loading="lazy"
              />
            </div>
          </div>
          <div className="overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-2 shadow-2xl shadow-black/50">
            <div className="relative aspect-[16/9] w-full overflow-hidden rounded-xl md:aspect-[2/1]">
              <Image
                src="/images/trade-history.webp"
                alt="Trade history and review in TradeTraxs"
                fill
                className="object-cover object-center"
                sizes="(max-width: 1024px) 100vw, 960px"
                loading="lazy"
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
