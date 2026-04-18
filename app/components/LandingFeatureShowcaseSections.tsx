"use client"

import { useEffect, useRef, useState } from "react"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
} from "@/lib/landingPageUi"

type ShowcaseBlock = {
  id: string
  reverse: boolean
  title: string
  subtitle: string
  bullets: string[]
  placeholderLabel: string
}

const BLOCKS: ShowcaseBlock[] = [
  {
    id: "showcase-dashboard",
    reverse: false,
    title: "See Your Trading Clearly",
    subtitle: "Not just P&L — real insights into how you actually trade.",
    bullets: [
      "Session performance tracking (NY, London, Asia)",
      "Win rate trends and consistency metrics",
      "Risk-reward analysis",
      "Daily, weekly, and monthly breakdowns",
    ],
    placeholderLabel: "Dashboard screenshot",
  },
  {
    id: "showcase-trade-input",
    reverse: true,
    title: "Log Trades Your Way",
    subtitle: "Fast manual entry or import everything in seconds.",
    bullets: [
      "Quick and clean manual trade entry",
      "CSV import support for bulk uploads",
      "Screenshot uploads for full context",
      "Custom fields like RR, session, and notes",
    ],
    placeholderLabel: "Trade input screenshot",
  },
  {
    id: "showcase-trade-review",
    reverse: false,
    title: "Review Every Trade With Context",
    subtitle: "Go beyond numbers — understand every decision you made.",
    bullets: [
      "Trade history with visual cards",
      "Screenshot-based review",
      "Notes and reasoning tracking",
      "Identify patterns and mistakes",
    ],
    placeholderLabel: "Trade history screenshot",
  },
  {
    id: "showcase-messaging",
    reverse: true,
    title: "Talk Trades. Share Ideas. Improve Faster.",
    subtitle: "Built-in messaging and real conversations — not random forums.",
    bullets: [
      "Direct messaging between traders",
      "Real-time trade discussions",
      "Learn from others in the platform",
      "Stay connected with your trading network",
    ],
    placeholderLabel: "Messaging UI screenshot",
  },
  {
    id: "showcase-ai",
    reverse: false,
    title: "Get Instant Feedback On Your Trades",
    subtitle: "AI-powered insights to help you improve faster.",
    bullets: [
      "Analyze trades automatically",
      "Identify mistakes and patterns",
      "Get actionable feedback",
      "Improve decision-making over time",
    ],
    placeholderLabel: "AI analysis screenshot",
  },
]

function FeatureSplitSection({ block }: { block: ShowcaseBlock }) {
  const ref = useRef<HTMLElement>(null)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVisible(true)
      return
    }
    const el = ref.current
    if (!el) return
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setVisible(true)
          io.unobserve(el)
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -5% 0px" }
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  return (
    <section
      ref={ref}
      id={block.id}
      className={`relative z-10 scroll-mt-24 border-t border-white/10 px-6 py-16 md:py-20 lg:py-24 transition-[opacity,transform] duration-[400ms] ease-out ${LANDING_REVEAL_TRANSITION} ${
        visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM
      }`}
      aria-labelledby={`${block.id}-heading`}
    >
      <div className="mx-auto max-w-6xl">
        <div
          className={`flex flex-col gap-10 lg:flex-row lg:items-center lg:gap-14 ${block.reverse ? "lg:flex-row-reverse" : ""}`}
        >
          <div className="min-w-0 flex-1 space-y-5 text-left">
            <h2
              id={`${block.id}-heading`}
              className="text-3xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl"
            >
              {block.title}
            </h2>
            <p className="text-base leading-relaxed text-gray-400 md:text-lg">{block.subtitle}</p>
            <ul className="space-y-3 text-sm leading-relaxed text-gray-300 md:text-[15px]">
              {block.bullets.map((line) => (
                <li key={line} className="flex gap-3">
                  <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-400/75" aria-hidden />
                  <span>{line}</span>
                </li>
              ))}
            </ul>
          </div>

          <div className="min-w-0 flex-1">
            <div
              className="flex aspect-[4/3] w-full flex-col items-center justify-center rounded-2xl border border-dashed border-white/15 bg-gradient-to-br from-white/[0.04] to-emerald-500/[0.03] px-6 py-8 shadow-inner shadow-black/20"
              aria-hidden
            >
              <span className="mb-2 text-[10px] font-semibold uppercase tracking-widest text-gray-500">
                Placeholder
              </span>
              <span className="text-center text-sm text-gray-500">{block.placeholderLabel}</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

export default function LandingFeatureShowcaseSections() {
  return (
    <div className="relative z-10">
      {BLOCKS.map((block) => (
        <FeatureSplitSection key={block.id} block={block} />
      ))}
    </div>
  )
}
