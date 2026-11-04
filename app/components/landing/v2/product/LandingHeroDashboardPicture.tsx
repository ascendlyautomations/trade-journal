"use client"

import dynamic from "next/dynamic"
import Image from "next/image"
import { useState } from "react"
import LandingDemoDataBadge from "./LandingDemoDataBadge"

const ImageLightbox = dynamic(() => import("@/app/components/ui/ImageLightbox"))

/** Full dashboard export — `public/images/dashboard.webp`. */
const DASHBOARD_SHOT_WIDTH = 1897
const DASHBOARD_SHOT_HEIGHT = 954

/** Marketing hero — `public/images/hero-dashboard-performance.png` (user export). */
const HERO_SHOT_SRC = "/images/hero-dashboard-performance.png"
const HERO_SHOT_WIDTH = 1024
const HERO_SHOT_HEIGHT = 534

const DASHBOARD_ALT =
  "TradeTraxs dashboard with performance analytics, equity curve, and journal stats"

type LandingHeroDashboardPictureProps = {
  /** Side-by-side marketing hero: hero-dashboard-performance.png, no demo badge. */
  variant?: "default" | "hero-side"
}

function MagnifyIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      aria-hidden
    >
      <circle cx="8.5" cy="8.5" r="5.25" />
      <path d="M13 13l4 4" strokeLinecap="round" />
    </svg>
  )
}

export default function LandingHeroDashboardPicture({
  variant = "default",
}: LandingHeroDashboardPictureProps) {
  const heroSide = variant === "hero-side"
  const [lightboxOpen, setLightboxOpen] = useState(false)

  const src = heroSide ? HERO_SHOT_SRC : "/images/dashboard.webp"
  const width = heroSide ? HERO_SHOT_WIDTH : DASHBOARD_SHOT_WIDTH
  const height = heroSide ? HERO_SHOT_HEIGHT : DASHBOARD_SHOT_HEIGHT

  const photoFrame = (
    <div className="tt-hero-dashboard-photo-frame">
      <Image
        src={src}
        alt={DASHBOARD_ALT}
        width={width}
        height={height}
        className="tt-hero-dashboard-photo"
        priority={heroSide}
        quality={heroSide ? 100 : 92}
        unoptimized={heroSide}
        sizes={
          heroSide
            ? "(max-width: 767px) 92vw, 960px"
            : "(max-width: 640px) 100vw, (max-width: 1024px) 92vw, 1100px"
        }
      />
    </div>
  )

  return (
    <div
      className={`tt-hero-dashboard-embed-wrap${heroSide ? " tt-hero-dashboard-embed-wrap--hero-side" : ""}`}
    >
      {heroSide ? (
        <>
          <button
            type="button"
            className="tt-hero-dashboard-photo-trigger group"
            onClick={() => setLightboxOpen(true)}
            aria-label={`View larger: ${DASHBOARD_ALT}`}
          >
            {photoFrame}
            <span className="tt-hero-dashboard-photo-enlarge" aria-hidden>
              <MagnifyIcon className="tt-hero-dashboard-photo-enlarge-icon" />
              Click to enlarge
            </span>
          </button>
          {lightboxOpen ? (
            <ImageLightbox
              imageUrl={src}
              alt={DASHBOARD_ALT}
              belowNavbar
              onClose={() => setLightboxOpen(false)}
            />
          ) : null}
        </>
      ) : (
        photoFrame
      )}
      {heroSide ? null : (
        <div className="tt-hero-dashboard-embed-foot">
          <LandingDemoDataBadge />
        </div>
      )}
    </div>
  )
}
