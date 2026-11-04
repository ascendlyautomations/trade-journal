"use client"

import Image from "next/image"
import type { RefObject } from "react"
import LandingExploreLink from "./LandingExploreLink"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"
import type { MarketingAppDestinationId } from "@/lib/marketingAppExplore"
import { InsightsDualShowcase } from "./product/LandingCompactPreviews"

const PLATFORM_TILES: {
  title: string
  detail: string
  image: string
  alt: string
  explore: MarketingAppDestinationId
}[] = [
  {
    title: "Prop Firm Mode",
    detail: "Rules & funded progress",
    image: "/images/Prop_Firm_Mode_Showcase.png",
    alt: "TradeTraxs Prop Firm Mode with requirements, payout status, and equity curve",
    explore: "propfirm",
  },
  {
    title: "Trade Rooms",
    detail: "Groups for markets",
    image: "/images/Trade_Rooms.webp",
    alt: "Trade Rooms with channels and group chat",
    explore: "rooms",
  },
  {
    title: "Profiles",
    detail: "Your public progress",
    image: "/images/Trader_Profiles_Showcase.png",
    alt: "TradeTraxs trader profile with stats, payouts, and achievements",
    explore: "profiles",
  },
  {
    title: "Leaderboards",
    detail: "Community rankings",
    image: "/images/Leaderboard_Dark_Showcase.png",
    alt: "TradeTraxs community leaderboard in dark mode with rankings and P&L chart",
    explore: "leaderboard",
  },
  {
    title: "Achievements",
    detail: "Milestones that stick",
    image: "/images/Achievements_Showcase.png",
    alt: "TradeTraxs profile achievements including milestones and prop firm payouts",
    explore: "achievements",
  },
  {
    title: "Social Feed",
    detail: "Trades, clips & posts",
    image: "/images/Social_Feed_Showcase.png",
    alt: "TradeTraxs social feed with shared trades, chart posts, and suggested traders",
    explore: "feed",
  },
]

function PlatformTile({
  title,
  detail,
  image,
  alt,
  explore,
}: (typeof PLATFORM_TILES)[number]) {
  return (
    <article className="tt-platform-tile">
      <div className="tt-platform-tile-visual">
        <Image
          src={image}
          alt={alt}
          width={640}
          height={400}
          className="tt-platform-tile-img"
          sizes="(max-width: 640px) 45vw, 200px"
          quality={86}
        />
      </div>
      <div className="tt-platform-tile-copy">
        <h4>{title}</h4>
        <p>{detail}</p>
        <LandingExploreLink destination={explore} className="tt-explore-link--tile" />
      </div>
    </article>
  )
}

export default function LandingFeaturesSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      id="features"
      className="tt-section tt-section--features scroll-mt-24"
      aria-labelledby="features-heading"
    >
      <div
        ref={ref as RefObject<HTMLDivElement>}
        className="tt-section-inner tt-platform-inner"
      >
        <div
          className={`tt-platform-intro tt-platform-intro--features-only ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p id="features-heading" className="tt-section-eyebrow">
            Inside the platform
          </p>
        </div>

        <div
          className={`tt-platform-showcases ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-75 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <article className="tt-platform-showcase tt-platform-showcase--insights" aria-labelledby="showcase-insights">
            <header className="tt-platform-showcase-header tt-platform-showcase-header--center tt-platform-showcase-header--insights">
              <h3 id="showcase-insights" className="tt-platform-showcase-title">
                Understand the Numbers. And What&apos;s Behind Them.
              </h3>
              <p className="tt-platform-showcase-lede">
                Go beyond your P&amp;L. Explore your performance, recognize trading patterns, and
                discover how sleep, mood, stress, and focus relate to your results.
              </p>
            </header>
            <InsightsDualShowcase />
          </article>

          <article className="tt-platform-showcase tt-platform-showcase--compass" aria-labelledby="showcase-compass">
            <header className="tt-platform-showcase-header tt-platform-showcase-header--center">
              <h3 id="showcase-compass" className="tt-platform-showcase-title tt-platform-showcase-title--sm">
                Custom Built Around Your Entire Trading Journey.
              </h3>
              <p className="tt-platform-showcase-lede">
                Choose between light, dark, or TradeTraxs appearance
              </p>
            </header>
            <div className="tt-platform-compass-grid">
              {PLATFORM_TILES.map((tile) => (
                <PlatformTile key={tile.title} {...tile} />
              ))}
            </div>
          </article>
        </div>
      </div>
    </section>
  )
}
