"use client"

import type { RefObject } from "react"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  useLandingReveal,
} from "@/lib/landingPageUi"
import LandingAppStoreButton from "./LandingAppStoreButton"
import LandingIosMarketingPreview from "./product/LandingIosMarketingPreview"

type Props = {
  onStartTrial: () => void
  trialCtaLabel: string
  checkoutLoading: boolean
  loading: boolean
}

export default function LandingIosSection({
  onStartTrial,
  trialCtaLabel,
  checkoutLoading,
  loading,
}: Props) {
  const { ref, visible } = useLandingReveal()

  return (
    <section className="tt-section tt-section--ios" aria-labelledby="ios-heading">
      <div className="tt-section-inner tt-ios-layout">
        <div
          ref={ref as RefObject<HTMLDivElement>}
          className={`tt-ios-copy ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className="tt-section-eyebrow">Native iOS</p>
          <h2 id="ios-heading" className="tt-section-title">
            The connected platform in your pocket.
          </h2>
          <p className="tt-section-lede tt-ios-lede">
            Log trades, review stats, scroll the Feed, and stay in rooms and messages, same account,
            same data as web. TradeTraxs on iPhone is the native extension of the platform, not a
            stripped-down companion app.
          </p>
          <div className="tt-ios-actions">
            <LandingAppStoreButton surface="ios_section" />
            <button
              type="button"
              className="tt-btn tt-btn-secondary"
              disabled={checkoutLoading || loading}
              onClick={onStartTrial}
            >
              {trialCtaLabel} on web
            </button>
          </div>
          <p className="tt-ios-note">Android is in development. iOS is the shipped native app today.</p>
        </div>

        <div
          className={`tt-ios-device ${LANDING_REVEAL_TRANSITION} delay-150 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <LandingIosMarketingPreview />
        </div>
      </div>
    </section>
  )
}
