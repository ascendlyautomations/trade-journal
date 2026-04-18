"use client"

import {
  LANDING_CARD_FULL,
  LANDING_CARD_PADDING,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_TITLE_GRADIENT,
  useLandingReveal,
} from "@/lib/landingPageUi"

const FEATURES: {
  title: string
  body: string
  highlight?: boolean
}[] = [
  {
    title: "Dashboard Analytics",
    body: "Equity curve, sessions, win rate—your edge in one glance.",
  },
  {
    title: "Trading Calendar",
    body: "Day-by-day clarity: see where your setups actually print.",
  },
  {
    title: "Trade History",
    body: "Full data plus screenshots on every trade you log.",
  },
  {
    title: "AI Trade Analysis",
    body: "Instant feedback on what worked, what broke, and what to tighten next.",
    highlight: true,
  },
  {
    title: "Community Feed",
    body: "Share trades with context. Learn from executions—not opinions.",
    highlight: true,
  },
  {
    title: "Leaderboards",
    body: "Rankings built on performance—stack up on consistency.",
  },
]

export default function LandingFeatureGridSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="features-grid"
      className="relative z-10 mx-auto max-w-6xl border-t border-white/10 px-6 py-24"
      aria-labelledby="features-grid-heading"
    >
      <div
        className={`mx-auto mb-14 max-w-3xl space-y-4 text-center ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
      >
        <h2
          id="features-grid-heading"
          className="text-4xl font-extrabold tracking-tight text-white drop-shadow-lg"
        >
          Everything You Need.{" "}
          <span className={LANDING_TITLE_GRADIENT}>In One Place.</span>
        </h2>
        <p className="text-base leading-relaxed text-gray-400">
          Log it. Break it down. Share it. Level up.
        </p>
      </div>

      <div className="grid grid-cols-1 items-stretch gap-6 sm:grid-cols-2 sm:gap-6 lg:grid-cols-3 lg:gap-8">
        {FEATURES.map((item, i) => (
          <div
            key={item.title}
            className={`flex min-h-[168px] flex-col ${LANDING_CARD_FULL} ${LANDING_CARD_PADDING} ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM} ${
              item.highlight
                ? "border-emerald-400/25 bg-gradient-to-br from-white/[0.06] to-emerald-500/[0.04] ring-1 ring-emerald-400/20"
                : ""
            }`}
            style={{
              transitionDelay: visible ? `${i * 75}ms` : "0ms",
            }}
          >
            <h3 className="mb-3 text-lg font-semibold text-emerald-300">{item.title}</h3>
            <p className="flex-1 text-sm leading-relaxed text-gray-400">{item.body}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
