"use client"

import Image from "next/image"
import {
  LANDING_CARD_FULL,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_TITLE_GRADIENT,
  useLandingReveal,
} from "@/lib/landingPageUi"

const COMMUNITY_ITEMS = [
  {
    title: "Social feed",
    img: "/images/social-feed.png",
    objectPosition: "object-top",
    bullets: [
      "Follow traders you respect",
      "Share charts and thoughts",
      "Discuss setups and psychology",
      "Discover new edges",
    ],
  },
  {
    title: "Public profiles",
    img: "/images/public-profiles.png",
    objectPosition: "object-top",
    bullets: [
      "Showcase performance",
      "Share strategy tags",
      "Let others learn from your journey",
    ],
  },
  {
    title: "Leaderboards & accountability",
    img: "/images/leaderboard.png",
    objectPosition: "object-center",
    bullets: [
      "Compare stats with peers",
      "Rank by P&L, win rate, and consistency",
      "Stay motivated with visibility",
    ],
  },
  {
    title: "Community learning",
    img: "/images/community-learning.png",
    objectPosition: "object-center",
    bullets: [
      "Learn from shared mistakes",
      "Ask questions and get feedback",
      "Grow faster together",
    ],
  },
] as const

export default function LandingCommunitySection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="community"
      className="relative overflow-hidden px-6 py-24 md:py-28"
    >
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_70%_30%,rgba(52,211,153,0.06),transparent_55%),radial-gradient(circle_at_25%_75%,rgba(96,165,250,0.06),transparent_55%)]" />

      <div className="relative mx-auto max-w-6xl">
        <div
          className={`mx-auto mb-14 max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <h2 className="text-3xl font-semibold tracking-tight text-white md:text-4xl">
            Community &{" "}
            <span className={LANDING_TITLE_GRADIENT}>Insights</span>
          </h2>
          <p className="mt-4 text-lg text-zinc-400 md:text-xl">
            Share ideas, compare stats, and learn together — without turning
            trading into noise.
          </p>
        </div>

        <div className="grid gap-6 md:grid-cols-2 md:gap-8">
          {COMMUNITY_ITEMS.map((item, i) => (
            <article
              key={item.title}
              className={`group relative flex flex-col overflow-hidden ${LANDING_CARD_FULL} ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
              style={{
                transitionDelay: visible ? `${i * 75}ms` : "0ms",
              }}
            >
              <div className="relative h-[260px] w-full shrink-0 overflow-hidden md:h-[320px] lg:h-[360px]">
                <Image
                  src={item.img}
                  alt=""
                  fill
                  className={`object-cover transition-transform duration-[400ms] ease-out group-hover:scale-[1.03] motion-reduce:group-hover:scale-100 ${item.objectPosition}`}
                  sizes="(max-width: 768px) 100vw, 50vw"
                  loading="lazy"
                />
              </div>
              <div className="flex flex-1 flex-col p-6 md:p-8">
                <h3 className="text-xl font-semibold text-white">
                  {item.title}
                </h3>
                <ul className="mt-4 space-y-2.5 text-zinc-400">
                  {item.bullets.map((b) => (
                    <li key={b} className="flex gap-3 text-[15px] leading-relaxed">
                      <span
                        className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-400/80"
                        aria-hidden
                      />
                      <span>{b}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
