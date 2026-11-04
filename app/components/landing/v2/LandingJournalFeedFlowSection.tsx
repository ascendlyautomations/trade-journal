"use client"

import type { RefObject } from "react"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"
import { JournalFeedFlowShowcase } from "./product/LandingCompactPreviews"

/** Journal → Feed flow, placed directly under the homepage hero. */
export default function LandingJournalFeedFlowSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      className="tt-section tt-section--journal-feed scroll-mt-24"
      aria-labelledby="journal-feed-flow-heading"
    >
      <div ref={ref as RefObject<HTMLDivElement>} className="tt-section-inner tt-platform-inner">
        <div
          className={`tt-platform-intro tt-platform-intro--journal-feed ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className="tt-section-eyebrow">Journal to community</p>
          <h2 id="journal-feed-flow-heading" className="tt-section-title">
            One trade, shared across the platform
          </h2>
          <p className="tt-section-lede tt-section-lede--center">
            Log a trade in your journal with your chart and an optional breakdown clip, then share
            the same record to the Feed when you are ready. One trade, one clip, no copy-paste.
          </p>
        </div>

        <article
          className={`tt-platform-showcase tt-platform-showcase--primary tt-journal-feed-flow-hero ${LANDING_REVEAL_TRANSITION} transition-all duration-500 delay-75 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
          aria-label="From journal entry to feed share"
        >
          <div className="tt-platform-showcase-canvas tt-platform-showcase-canvas--hero">
            <JournalFeedFlowShowcase />
          </div>
        </article>
      </div>
    </section>
  )
}
