"use client"

import LandingShowcaseImage from "@/app/components/landing/LandingShowcaseImage"
import {
  LANDING_HEADLINE_SM,
  LANDING_LEAD_GAP,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_SECTION_CONTENT_GAP,
  LANDING_TITLE_GRADIENT,
  useLandingReveal,
} from "@/lib/landingPageUi"

export default function LandingAnalyticsShowcaseSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="analytics"
      className={`relative z-10 border-t border-white/10 px-4 py-12 md:px-6 md:py-28 ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
      aria-labelledby="analytics-heading"
    >
      <div className="mx-auto max-w-6xl">
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="analytics-heading" className={LANDING_HEADLINE_SM}>
            Know Your{" "}
            <span className={LANDING_TITLE_GRADIENT}>Edge</span>
          </h2>
          <p className={`text-base leading-relaxed text-gray-400 md:text-xl ${LANDING_LEAD_GAP}`}>
            Every trade tells a story. TradeTraxs helps you discover it.
          </p>
        </div>

        <div className="mt-8 flex justify-center md:mt-16">
          <div className="w-[94%] max-w-full sm:w-[92%] md:w-[90%] lg:w-[87%]">
            <LandingShowcaseImage
              src="/images/Know_Your_Edge.webp"
              alt="TradeTraxs analytics, know your edge with performance insights"
              objectPositionClass="object-top"
              size="large"
            />
          </div>
        </div>
      </div>
    </section>
  )
}
