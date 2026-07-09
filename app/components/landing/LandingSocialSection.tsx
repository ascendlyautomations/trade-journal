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

const SOCIAL_SHOTS = [
  {
    src: "/images/social-feed.webp",
    alt: "TradeTraxs community feed with posts, likes, and comments",
    label: "Feed",
  },
  {
    src: "/images/public-profiles.webp",
    alt: "Trader profiles to build a following on TradeTraxs",
    label: "Profiles",
  },
  {
    src: "/images/community-learning.webp",
    alt: "Traders learning and sharing on TradeTraxs",
    label: "Community",
  },
  {
    src: "/images/messaging-ui-v2.webp",
    alt: "Trade rooms and real-time trader chat",
    label: "Trade rooms",
  },
] as const

export default function LandingSocialSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="social"
      className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="social-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center lg:gap-16">
          <div
            className={`${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
          >
            <p className={LANDING_EYEBROW}>Community</p>
            <h2 id="social-heading" className={`${LANDING_HEADLINE_SM} mt-4`}>
              This isn&apos;t another trading journal.
            </h2>
            <p className={`${LANDING_LEAD} mt-5`}>
              Where traders connect, share, and grow — with tracking and analytics built in.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-4">
            {SOCIAL_SHOTS.map((shot, i) => (
              <figure
                key={shot.label}
                className={`overflow-hidden rounded-xl border border-white/[0.08] bg-white/[0.02] ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
                style={{ transitionDelay: visible ? `${i * 60}ms` : "0ms" }}
              >
                <div className="relative aspect-[4/3] w-full">
                  <Image
                    src={shot.src}
                    alt={shot.alt}
                    fill
                    className="object-cover object-top"
                    sizes="(max-width: 768px) 50vw, 280px"
                    loading="lazy"
                  />
                </div>
                <figcaption className="px-3 py-2 text-xs font-medium text-zinc-500">
                  {shot.label}
                </figcaption>
              </figure>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
