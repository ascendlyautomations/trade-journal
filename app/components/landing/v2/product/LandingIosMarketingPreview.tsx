"use client"

import { LandingIosAppScreenshot } from "./LandingCompactPreviews"
import LandingDemoDataBadge from "./LandingDemoDataBadge"

type Props = { className?: string }

export default function LandingIosMarketingPreview({ className = "" }: Props) {
  return (
    <div className={className}>
      <div className="mb-2 flex items-center justify-end gap-2 md:hidden">
        <LandingDemoDataBadge />
      </div>
      <LandingIosAppScreenshot />
    </div>
  )
}
