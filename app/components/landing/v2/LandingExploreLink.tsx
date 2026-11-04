"use client"

import {
  MARKETING_APP_DESTINATIONS,
  navigateMarketingAppExplore,
  type MarketingAppDestinationId,
} from "@/lib/marketingAppExplore"

type LandingExploreLinkProps = {
  destination: MarketingAppDestinationId
  className?: string
}

export default function LandingExploreLink({
  destination,
  className = "",
}: LandingExploreLinkProps) {
  const dest = MARKETING_APP_DESTINATIONS[destination]

  return (
    <button
      type="button"
      className={`tt-explore-link ${className}`.trim()}
      onClick={() => {
        void navigateMarketingAppExplore(destination)
      }}
    >
      {dest.exploreLabel}
      <span className="tt-explore-link-arrow" aria-hidden>
        →
      </span>
    </button>
  )
}
