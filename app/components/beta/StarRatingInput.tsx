"use client"

import { memo } from "react"

type StarRatingInputProps = {
  value: number
  onChange: (rating: number) => void
  disabled?: boolean
  size?: "sm" | "md"
}

function StarRatingInput({
  value,
  onChange,
  disabled = false,
  size = "md",
}: StarRatingInputProps) {
  const starClass = size === "sm" ? "text-lg" : "text-2xl"

  return (
    <div className="flex items-center gap-1" role="radiogroup" aria-label="Rating">
      {[1, 2, 3, 4, 5].map((star) => {
        const filled = star <= value
        return (
          <button
            key={star}
            type="button"
            role="radio"
            aria-checked={filled}
            aria-label={`${star} star${star === 1 ? "" : "s"}`}
            disabled={disabled}
            onClick={() => onChange(star)}
            className={`${starClass} transition hover:scale-110 disabled:cursor-not-allowed disabled:opacity-60 motion-reduce:hover:scale-100`}
          >
            {filled ? "⭐" : "☆"}
          </button>
        )
      })}
    </div>
  )
}

export default memo(StarRatingInput)
