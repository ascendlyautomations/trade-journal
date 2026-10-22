"use client"

import { useContextualTourOptional } from "@/lib/contextualTour/ContextualTourProvider"
import { isNativeIos } from "@/lib/nativePlatform"

type Props = {
  className?: string
  label?: string
}

export default function ContextualTourReplayButton({
  className = "",
  label = "Replay app walkthrough",
}: Props) {
  const tour = useContextualTourOptional()
  if (typeof window !== "undefined" && isNativeIos()) return null
  if (!tour) return null

  return (
    <button
      type="button"
      className={className}
      onClick={() => tour.beginReplay()}
    >
      {label}
    </button>
  )
}
