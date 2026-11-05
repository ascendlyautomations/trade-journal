"use client"

import LandingHeroDashboardPicture from "./product/LandingHeroDashboardPicture"

type Props = {
  trialCtaLabel: string
  checkoutLoading: boolean
  loading: boolean
  onStartTrial: () => void
  onExploreDemo: () => void
}

export default function LandingHeroSection({
  trialCtaLabel,
  checkoutLoading,
  loading,
  onStartTrial,
  onExploreDemo,
}: Props) {
  return (
    <section className="tt-hero tt-hero--split" aria-labelledby="home-heading">
      <div className="tt-hero-bg" aria-hidden>
        <div className="tt-hero-grid" />
        <div className="tt-hero-orb tt-hero-orb--a" />
        <div className="tt-hero-orb tt-hero-orb--b" />
      </div>

      <div className="tt-hero-inner tt-hero-inner--split">
        <div className="tt-hero-copy tt-hero-copy--split">
          <p className="tt-hero-eyebrow">Trading platform · Web & iOS</p>
          <h1 id="home-heading" className="tt-hero-title">
            More Than a Trading Journal.
            <span className="tt-hero-title-accent">A Platform Built for Traders.</span>
          </h1>
          <p className="tt-hero-lede">
            Journal your trades, analyze your performance, and connect with a community of
            traders, all in one place. From tracking your progress to sharing your biggest
            milestones, TradeTraxs brings every part of your trading journey together.
          </p>
          <div className="tt-hero-actions">
            <button
              type="button"
              className="tt-btn tt-btn-primary"
              disabled={checkoutLoading || loading}
              onClick={onStartTrial}
            >
              {trialCtaLabel}
            </button>
            <button type="button" className="tt-btn tt-btn-secondary" onClick={onExploreDemo}>
              Explore the Demo
            </button>
          </div>
          <p className="tt-hero-app-note">Free to start · No credit card required</p>
        </div>
        <div className="tt-hero-visual-side">
          <LandingHeroDashboardPicture variant="hero-side" />
        </div>
      </div>
    </section>
  )
}
