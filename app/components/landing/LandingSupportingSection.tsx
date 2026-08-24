"use client"

import { LANDING_FLAGSHIPS } from "@/lib/landingFlagships"
import {
  LANDING_EYEBROW,
  LANDING_HEADLINE_SM,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  useLandingReveal,
} from "@/lib/landingPageUi"

const LANDING_SUPPORTING_FEATURES = LANDING_FLAGSHIPS.flatMap((flagship) =>
  (flagship.bonuses?.split(" · ") ?? []).map((title) => ({
    title,
    tagline: flagship.title,
  }))
)

export default function LandingSupportingSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="supporting"
      className={`${LANDING_SECTION_BORDER} py-16 md:py-20`}
      aria-labelledby="supporting-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div
          className={`mx-auto max-w-2xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className={LANDING_EYEBROW}>Also included</p>
          <h2 id="supporting-heading" className={`${LANDING_HEADLINE_SM} mt-4 text-2xl md:text-3xl`}>
            Everything else, connected.
          </h2>
        </div>

        <ul
          className={`mx-auto mt-10 grid max-w-4xl gap-3 sm:grid-cols-2 lg:grid-cols-3 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-75 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          {LANDING_SUPPORTING_FEATURES.map((feature) => (
            <li
              key={feature.title}
              className="rounded-xl border border-white/[0.06] bg-white/[0.02] px-4 py-3.5"
            >
              <p className="text-sm font-medium text-zinc-300">{feature.title}</p>
              <p className="mt-0.5 text-xs text-zinc-500">{feature.tagline}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
