"use client"

import {
  LANDING_CARD_FULL,
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

const ECOSYSTEM_FLOW = [
  { step: "Connect", features: "Feed · Profiles · Follow" },
  { step: "Collaborate", features: "Rooms · Clips · Comments" },
  { step: "Track", features: "Journal · Calendar" },
  { step: "Improve", features: "Analytics · AI · Prop Firm" },
] as const

const ECOSYSTEM = [
  {
    title: "Community Feed",
    description: "See what traders are doing, learning, and sharing in real time.",
    tag: "Social",
  },
  {
    title: "Trade Rooms",
    description: "Trade alongside your network — live discussion, shared context.",
    tag: "Social",
  },
  {
    title: "Clips",
    description: "Watch and share short-form trading content that moves fast.",
    tag: "Social",
  },
  {
    title: "Achievements",
    description: "Celebrate milestones and show the progress you’re making.",
    tag: "Social",
  },
  {
    title: "Leaderboards",
    description: "See where you stand and push yourself against the community.",
    tag: "Social",
  },
  {
    title: "Trade Journal",
    description: "Capture every trade with the context you need to learn from it.",
    tag: "Core",
  },
  {
    title: "Performance Dashboard",
    description: "Understand what’s working — and what’s quietly costing you.",
    tag: "Analytics",
  },
  {
    title: "AI Analyst",
    description: "Get a second opinion on patterns, entries, and habits.",
    tag: "TraxPro",
  },
  {
    title: "Prop Firm Mode",
    description: "Stay funded — track rules, drawdown, and payout progress.",
    tag: "TraxPro",
  },
  {
    title: "Calendar",
    description: "Review your trading days and spot trends over time.",
    tag: "Analytics",
  },
] as const

const TAG_COLORS: Record<string, string> = {
  Core: "text-blue-300 bg-blue-500/10 border-blue-500/20",
  Analytics: "text-sky-300 bg-sky-500/10 border-sky-500/20",
  TraxPro: "text-amber-200 bg-amber-500/10 border-amber-500/20",
  Social: "text-emerald-300 bg-emerald-500/10 border-emerald-500/20",
}

export default function LandingEcosystemSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="ecosystem"
      className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="ecosystem-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div
          className={`mx-auto max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className={LANDING_EYEBROW}>One connected platform</p>
          <h2 id="ecosystem-heading" className={`${LANDING_HEADLINE_SM} mt-4`}>
            Community at the center. Everything else connected.
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-6`}>
            Journaling and analytics are powerful — but they&apos;re one part of a bigger picture.
            TradeTraxs ties social, tracking, and insight together so you grow faster together.
          </p>
        </div>

        <div
          className={`mx-auto mt-12 flex max-w-4xl flex-col items-stretch gap-3 sm:flex-row sm:items-center sm:justify-center sm:gap-2 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
          aria-label="How TradeTraxs connects your trading journey"
        >
          {ECOSYSTEM_FLOW.map((item, i) => (
            <div key={item.step} className="flex flex-1 items-center gap-2 sm:flex-col sm:gap-1">
              {i > 0 && (
                <span className="hidden shrink-0 text-zinc-600 sm:inline" aria-hidden>
                  →
                </span>
              )}
              <div className="flex-1 rounded-xl border border-white/[0.08] bg-white/[0.03] px-4 py-3 text-center sm:min-w-[140px] sm:flex-none">
                <p className="text-sm font-semibold text-white">{item.step}</p>
                <p className="mt-0.5 text-[11px] text-zinc-500">{item.features}</p>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 lg:gap-5">
          {ECOSYSTEM.map((item, i) => (
            <article
              key={item.title}
              className={`${LANDING_CARD_FULL} flex flex-col p-6 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
              style={{ transitionDelay: visible ? `${i * 40}ms` : "0ms" }}
            >
              <span
                className={`inline-flex w-fit rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${TAG_COLORS[item.tag] ?? TAG_COLORS.Core}`}
              >
                {item.tag}
              </span>
              <h3 className="mt-4 text-lg font-semibold text-white">{item.title}</h3>
              <p className="mt-2 flex-1 text-sm leading-relaxed text-zinc-400">
                {item.description}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
