"use client"

import type { RefObject } from "react"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"

const HUB_SPOKES = [
  {
    id: "journal",
    title: "Trading journal",
    detail: "Your source of truth",
  },
  {
    id: "analytics",
    title: "Performance analytics",
    detail: "Patterns & review",
  },
  {
    id: "feed",
    title: "Social Feed",
    detail: "Share real trades",
  },
  {
    id: "rooms",
    title: "Trade Rooms",
    detail: "Trader group chats",
  },
  {
    id: "messages",
    title: "Messaging",
    detail: "Direct conversations",
  },
  {
    id: "profiles",
    title: "Profiles",
    detail: "Stats, Trades, Posts, Clips, Achievements",
  },
] as const

export default function LandingPlatformHubSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      className="tt-section tt-section--hub"
      aria-labelledby="platform-hub-heading"
    >
      <div className="tt-section-inner">
        <div
          ref={ref as RefObject<HTMLDivElement>}
          className={`tt-section-head tt-section-head--center ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className="tt-section-eyebrow">All in one platform</p>
          <h2 id="platform-hub-heading" className="tt-section-title">
            Your Trades Don&apos;t Belong in Separate Apps.
          </h2>
          <p className="tt-section-lede tt-section-lede--center">
            Why journal in one place, analyze in another, and share your progress somewhere else?
            TradeTraxs connects your trading journal, performance analytics, and community so
            everything works together.
          </p>
        </div>

        <div
          className={`tt-platform-hub ${LANDING_REVEAL_TRANSITION} delay-75 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <div className="tt-platform-hub-core" aria-hidden={false}>
            <p className="tt-platform-hub-core-title">Log once. Use everywhere.</p>
            <p className="tt-platform-hub-core-sub">
              The same entry powers your dashboard, calendar, profile, and, when you choose, what
              you share publicly or with your group.
            </p>
          </div>

          <ul className="tt-platform-hub-spokes">
            {HUB_SPOKES.map((spoke) => (
              <li key={spoke.id} className={`tt-platform-hub-spoke tt-platform-hub-spoke--${spoke.id}`}>
                <span className="tt-platform-hub-spoke-dot" aria-hidden />
                <div className="tt-platform-hub-spoke-body">
                  <p className="tt-platform-hub-spoke-title">{spoke.title}</p>
                  <p className="tt-platform-hub-spoke-detail">{spoke.detail}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  )
}
