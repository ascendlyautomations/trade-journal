"use client"

import type { RefObject } from "react"
import LandingExploreLink from "./LandingExploreLink"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"

const STEPS = [
  {
    step: "01",
    title: "Build your record",
    body: "Log trades manually, import CSVs, or sync supported brokers. Each entry keeps notes, screenshots, and context in one place, the foundation everything else runs on.",
  },
  {
    step: "02",
    title: "Learn from the data",
    body: "Dashboard, calendar, and stats read from the same trades you logged, so reviews reflect reality, not a spreadsheet you maintain on the side. TraxPro adds deeper analytics, Prop Firm Mode, AI review, and Backtest Lab.",
  },
  {
    step: "03",
    title: "Grow with the community",
    body: "Keep trades private for your own review, or share journaled results to the Feed, Trade Rooms, and DMs, with real P&L attached, not screenshots that lose context in generic chat apps.",
  },
] as const

export default function LandingHowItWorks() {
  const { ref, visible } = useLandingReveal()

  return (
    <section className="tt-section tt-section--how" aria-labelledby="how-heading">
      <div className="tt-section-inner">
        <div
          ref={ref as RefObject<HTMLDivElement>}
          className={`tt-section-head tt-section-head--center ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className="tt-section-eyebrow">How it works</p>
          <h2 id="how-heading" className="tt-section-title">
            One workflow from execution to improvement, and optional visibility.
          </h2>
          <p className="tt-section-lede tt-section-lede--center tt-section-lede--how">
            Traditional journals stop at the log. TradeTraxs starts there, then connects analysis,
            psychology, and community around the same trade record when you want them.
          </p>
        </div>

        <ol
          className={`tt-how-grid ${LANDING_REVEAL_TRANSITION} delay-100 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          {STEPS.map((item) => (
            <li key={item.step} className="tt-how-card">
              <span className="tt-how-step">{item.step}</span>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
              {item.step === "01" ? (
                <LandingExploreLink destination="journal" className="tt-explore-link--card" />
              ) : null}
              {item.step === "02" ? (
                <LandingExploreLink destination="analytics" className="tt-explore-link--card" />
              ) : null}
              {item.step === "03" ? (
                <LandingExploreLink destination="feed" className="tt-explore-link--card" />
              ) : null}
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
