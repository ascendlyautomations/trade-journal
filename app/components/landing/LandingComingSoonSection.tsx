"use client"

import {
  LANDING_BODY,
  LANDING_CARD_FULL,
  LANDING_CARD_PADDING,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_LEAD_GAP,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_CONTENT_GAP,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  useLandingReveal,
} from "@/lib/landingPageUi"
import { useEffect } from "react"

export const COMING_SOON_SECTION_ID = "coming-soon"

type ComingSoonStatus =
  | "Coming Soon"
  | "In Development"
  | "Planned"
  | "Always Improving"

type ComingSoonCard = {
  icon: string
  title: string
  description: string
  bullets: readonly string[]
  status: ComingSoonStatus
}

const COMING_SOON_CARDS: readonly ComingSoonCard[] = [
  {
    icon: "🔗",
    title: "Live Broker Connections",
    description: "Automatically sync your trades without CSV uploads.",
    bullets: ["Tradovate", "NinjaTrader", "Rithmic"],
    status: "Coming Soon",
  },
  {
    icon: "🎙️",
    title: "Voice Chat",
    description: "Talk live with your trading group directly inside Trade Rooms.",
    bullets: ["Live voice channels", "Push-to-talk", "Community discussions"],
    status: "Coming Soon",
  },
  {
    icon: "📱",
    title: "Mobile Apps",
    description: "TradeTraxs everywhere.",
    bullets: ["iPhone", "Android", "Push Notifications"],
    status: "In Development",
  },
  {
    icon: "🤖",
    title: "AI Trading Coach",
    description: "The next evolution of AI analysis.",
    bullets: [
      "Personalized coaching",
      "Behavioral insights",
      "Smarter recommendations",
      "Continuous improvement tracking",
    ],
    status: "Coming Soon",
  },
  {
    icon: "📅",
    title: "Economic Calendar",
    description: "Stay ahead of market-moving events.",
    bullets: ["High-impact news", "Event filtering", "Built directly into TradeTraxs"],
    status: "Planned",
  },
  {
    icon: "⚡",
    title: "More Integrations",
    description: "TradeTraxs is expanding.",
    bullets: [
      "Additional prop firms",
      "More brokers",
      "Additional import options",
    ],
    status: "Always Improving",
  },
]

function statusBadgeClass(status: ComingSoonStatus): string {
  switch (status) {
    case "In Development":
      return "border-blue-400/30 bg-blue-500/10 text-blue-300"
    case "Planned":
      return "border-white/15 bg-white/5 text-gray-300"
    case "Always Improving":
      return "border-emerald-400/30 bg-emerald-500/10 text-emerald-300"
    case "Coming Soon":
    default:
      return "border-amber-400/30 bg-amber-500/10 text-amber-200"
  }
}

function scrollToComingSoonSection(behavior: ScrollBehavior = "smooth") {
  const el = document.getElementById(COMING_SOON_SECTION_ID)
  if (!el) return false
  el.scrollIntoView({ behavior, block: "start" })
  return true
}

export function navigateToComingSoonSection() {
  if (typeof window === "undefined") return
  if (window.location.pathname === "/") {
    scrollToComingSoonSection("smooth")
    window.history.replaceState(null, "", `#${COMING_SOON_SECTION_ID}`)
    return
  }
  window.location.assign(`/#${COMING_SOON_SECTION_ID}`)
}

export default function LandingComingSoonSection() {
  const { ref, visible } = useLandingReveal()

  useEffect(() => {
    if (typeof window === "undefined") return
    if (window.location.hash !== `#${COMING_SOON_SECTION_ID}`) return

    const preferReduced =
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const behavior: ScrollBehavior = preferReduced ? "auto" : "smooth"

    const timer = window.setTimeout(() => {
      scrollToComingSoonSection(behavior)
    }, 80)

    return () => window.clearTimeout(timer)
  }, [])

  return (
    <section
      ref={ref}
      id={COMING_SOON_SECTION_ID}
      className={`relative z-10 scroll-mt-20 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="coming-soon-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div
          className={`mx-auto max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${
            visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM
          }`}
        >
          <h2 id="coming-soon-heading" className={LANDING_HEADLINE_SM}>
            Coming Soon
          </h2>
          <p className={`${LANDING_LEAD} mx-auto ${LANDING_LEAD_GAP}`}>
            We&apos;re just getting started. Here&apos;s what&apos;s already in development for
            TradeTraxs.
          </p>
        </div>

        <ul
          className={`grid gap-3 sm:grid-cols-2 sm:gap-4 md:gap-5 ${LANDING_SECTION_CONTENT_GAP} ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-75 ${
            visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM
          }`}
        >
          {COMING_SOON_CARDS.map((card) => (
            <li key={card.title} className={`${LANDING_CARD_FULL} ${LANDING_CARD_PADDING}`}>
              <div className="flex items-start gap-3">
                <span className="mt-0.5 text-xl md:text-2xl" aria-hidden>
                  {card.icon}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-base font-semibold text-white md:text-lg">
                      {card.title}
                    </h3>
                    <span
                      className={`rounded-full border px-2.5 py-1 text-[11px] font-medium uppercase tracking-wide md:text-xs ${statusBadgeClass(card.status)}`}
                    >
                      {card.status}
                    </span>
                  </div>
                  <p className={`mt-1.5 ${LANDING_BODY}`}>{card.description}</p>
                </div>
              </div>

              <ul className="mt-4 space-y-1.5 border-t border-white/10 pt-4">
                {card.bullets.map((bullet) => (
                  <li
                    key={bullet}
                    className="flex items-start gap-2 text-sm text-gray-300 md:text-[15px]"
                  >
                    <span
                      className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-gradient-to-r from-blue-400 to-emerald-400"
                      aria-hidden
                    />
                    <span>{bullet}</span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ul>

        <div
          className={`mx-auto mt-10 max-w-2xl text-center md:mt-14 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-150 ${
            visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM
          }`}
        >
          <p className="text-base leading-relaxed text-gray-300 md:text-lg">
            TradeTraxs is constantly evolving. Every update is built from feedback from real
            traders.
          </p>
          <p className="mt-3 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-semibold text-transparent md:mt-4 md:text-xl">
            A lot more is on the way.
          </p>
        </div>
      </div>
    </section>
  )
}
