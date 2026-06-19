"use client"

import Image from "next/image"
import { useEffect, useRef, useState } from "react"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
} from "@/lib/landingPageUi"
import { TRAXPRO_PLAN_NAME } from "@/lib/traxProPricing"

type ShowcaseBlock = {
  id: string
  reverse: boolean
  title: string
  subtitle: string
  bullets: string[]
  imageSrc?: string
  imageAlt?: string
  imageObjectPosition?: string
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
    imageSrc: "/images/dashboard.png",
    imageAlt: "Trading dashboard with analytics in TradeTraxs",
    imageObjectPosition: "object-center",
  },
  {
    id: "showcase-trade-input",
    reverse: true,
    title: "Log Trades Your Way",
    subtitle: "Fast manual entry or CSV import when you need it.",
    bullets: [
      "Quick and clean manual trade entry",
      "CSV import (1 on Free; unlimited on TraxPro)",
      "Screenshot uploads for full context",
      "Custom fields like RR, session, and notes",
    ],
    imageSrc: "/images/trade-input.png",
    imageAlt: "Trade entry and import options in TradeTraxs",
    imageObjectPosition: "object-top",
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
    imageSrc: "/images/trade-history.png",
    imageAlt: "Trade history with screenshots and notes in TradeTraxs",
    imageObjectPosition: "object-center",
  },
  {
    id: "showcase-messaging",
    reverse: true,
    title: "Talk Trades. Share Ideas. Improve Faster.",
    subtitle: "Built-in messaging and real conversations — not random forums.",
    bullets: [
      "Direct messaging between traders",
      "Group chats with other traders",
      "Learn from others on the platform",
      "Stay connected with your trading network",
    ],
    imageSrc: "/images/messaging-ui-v2.png",
    imageAlt: "Messaging and trade discussions in TradeTraxs",
    imageObjectPosition: "object-right",
  },
  {
    id: "showcase-ai",
    reverse: false,
    title: "Get Instant Feedback On Your Trades",
    subtitle: `AI-powered trade analysis on ${TRAXPRO_PLAN_NAME} to help you improve faster.`,
    bullets: [
      "Analyze trades automatically",
      "Identify mistakes and patterns",
      "Get actionable feedback",
      "Improve decision-making over time",
    ],
    // Screenshot: add imageSrc "/images/ai-analyst.png" when asset is captured from /analyst
  },
]

function ShowcaseFeatureImage({
  src,
  alt,
  objectPositionClass = "object-center",
}: {
  src: string
  alt: string
  objectPositionClass?: string
}) {
  return (
    <div className="group overflow-hidden rounded-2xl border border-emerald-400/20 bg-white/5 shadow-lg shadow-black/25 backdrop-blur-md transition-transform duration-300 ease-out hover:scale-[1.02] motion-reduce:transition-none motion-reduce:hover:scale-100">
      <div className="relative h-[260px] w-full overflow-hidden md:h-[320px] lg:h-[360px]">
        <Image
          src={src}
          alt={alt}
          fill
          className={`object-cover ${objectPositionClass}`}
          sizes="(max-width: 1024px) 100vw, 50vw"
          priority={false}
        />
      </div>
    </div>
  )
}

function layoutClassForBlock(block: ShowcaseBlock): string {
  if (block.id === "showcase-trade-input") {
    return "flex-col-reverse lg:flex-row-reverse"
  }
  if (
    block.id === "showcase-dashboard" ||
    block.id === "showcase-trade-review"
  ) {
    return "flex-col-reverse lg:flex-row"
  }
  if (block.id === "showcase-messaging") {
    return "flex-col-reverse lg:flex-row-reverse"
  }
  if (block.reverse) {
    return "flex-col lg:flex-row-reverse"
  }
  return "flex-col lg:flex-row"
}

function FeatureSplitSection({ block }: { block: ShowcaseBlock }) {
  const ref = useRef<HTMLElement>(null)
  const [visible, setVisible] = useState(false)
  const hasImage = Boolean(block.imageSrc && block.imageAlt)

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
      <div className={`mx-auto max-w-6xl ${hasImage ? "" : "max-w-3xl"}`}>
        <div
          className={`flex gap-10 lg:items-center lg:gap-14 ${layoutClassForBlock(block)}`}
        >
          <div className={`min-w-0 space-y-5 text-left ${hasImage ? "flex-1" : ""}`}>
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

          {hasImage ? (
            <div className="min-w-0 flex-1">
              <ShowcaseFeatureImage
                src={block.imageSrc!}
                alt={block.imageAlt!}
                objectPositionClass={block.imageObjectPosition ?? "object-center"}
              />
            </div>
          ) : null}
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
