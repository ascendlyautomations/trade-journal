"use client"

import {
  LANDING_CARD_FULL,
  LANDING_CARD_PADDING,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"

const BLOCKS = [
  {
    title: "Post Your Trades Like Content",
    body: "Setups, executions, results—the full story, not a screenshot of a PnL cell.",
    Icon: IconLayers,
  },
  {
    title: "Learn From Real Traders",
    body: "Watch how others enter, manage, and exit—no cherry-picked highlight reels.",
    Icon: IconUsers,
  },
  {
    title: "Real Feedback, Real Growth",
    body: "Perspective from people trading the same markets when it actually matters.",
    Icon: IconMessages,
  },
  {
    title: "Build Your Trading Identity",
    body: "A public profile and stats line that compounds credibility over time.",
    Icon: IconSparkles,
  },
  {
    title: "Stay Accountable",
    body: "Visibility changes the game—discipline stops being optional.",
    Icon: IconEye,
  },
  {
    title: "See What Actually Works",
    body: "Spot patterns across real trades — what wins, what fails, and what to repeat.",
    Icon: IconChartTrend,
  },
] as const

function IconLayers({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M12 2L4 6v12l8 4 8-4V6l-8-4zM4 10l8 4 8-4M4 14l8 4 8-4"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function IconUsers({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M17 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function IconMessages({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M21 15a4 4 0 0 1-4 4H8l-5 3v-7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4zM17 3H7a4 4 0 0 0-4 4v10"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function IconSparkles({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M12 3v2M12 19v2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M3 12h2M19 12h2M5.6 18.4l1.4-1.4M17 7l1.4-1.4"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
      />
      <circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.75" />
    </svg>
  )
}

function IconEye({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.75" />
    </svg>
  )
}

function IconChartTrend({ className }: { className?: string }) {
  return (
    <svg className={className} width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M4 19V5M4 19h15M8 14l3.5-4 3.5 3 4.5-7"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export default function LandingTradingContentSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="trading-content"
      className="relative z-10 mx-auto max-w-6xl border-t border-white/10 px-6 py-24"
      aria-labelledby="trading-content-heading"
    >
      <div
        className={`mx-auto mb-14 max-w-3xl space-y-4 text-center ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
      >
        <h2
          id="trading-content-heading"
          className="text-4xl font-extrabold tracking-tight text-white drop-shadow-lg"
        >
          Trading Alone Is Slowing You Down
        </h2>
        <p className="text-lg font-medium text-emerald-300/95">
          Solo journaling is quiet. Growth usually isn&apos;t.
        </p>
        <div className="space-y-2 text-base leading-relaxed text-gray-400">
          <p>No feedback loop. No accountability. No idea how anyone else actually trades.</p>
          <p className="text-gray-300">TradeTraxs gives you the social layer serious journaling skipped.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 md:gap-8 lg:grid-cols-3">
        {BLOCKS.map((item, i) => {
          const Icon = item.Icon
          return (
            <div
              key={item.title}
              className={`group flex min-h-[180px] flex-col ${LANDING_CARD_FULL} ${LANDING_CARD_PADDING} ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
              style={{
                transitionDelay: visible ? `${i * 75}ms` : "0ms",
              }}
            >
              <div className="mb-4 inline-flex rounded-lg border border-emerald-400/25 bg-emerald-500/10 p-2.5 text-emerald-300">
                <Icon className="shrink-0" />
              </div>
              <h3 className="mb-3 text-lg font-semibold text-emerald-300">{item.title}</h3>
              <p className="flex-1 text-sm leading-relaxed text-gray-400">{item.body}</p>
            </div>
          )
        })}
      </div>

      <p className="mx-auto mt-12 max-w-2xl text-center text-sm leading-relaxed text-gray-500">
        Where trading meets content—and content meets real markets.
      </p>
    </section>
  )
}
