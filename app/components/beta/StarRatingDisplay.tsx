"use client"

import { memo } from "react"

type StarRatingDisplayProps = {
  rating: number
  max?: number
  className?: string
}

function StarRatingDisplay({
  rating,
  max = 5,
  className = "",
}: StarRatingDisplayProps) {
  const rounded = Math.min(max, Math.max(0, Math.round(rating)))

  return (
    <span
      className={`inline-flex items-center gap-0.5 text-amber-300 ${className}`.trim()}
      aria-label={`${rating} out of ${max} stars`}
    >
      {Array.from({ length: max }, (_, index) => (
        <span key={index} aria-hidden>
          {index < rounded ? "★" : "☆"}
        </span>
      ))}
    </span>
  )
}

export default memo(StarRatingDisplay)
