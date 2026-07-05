"use client"

import { useMemo } from "react"
import ViewReelBadge from "@/app/components/feed/ViewReelBadge"
import { buildTradeTimingPresentation } from "@/lib/tradeTimingDisplay"

type TradeCardTimingBlockProps = {
  trade: Parameters<typeof buildTradeTimingPresentation>[0]
  className?: string
  onViewReel?: () => void
}

export default function TradeCardTimingBlock({
  trade,
  className = "text-xs text-gray-400",
  onViewReel,
}: TradeCardTimingBlockProps) {
  const timing = useMemo(() => buildTradeTimingPresentation(trade), [trade])

  if (!timing.priceRow && !timing.dateTimeRow && !onViewReel) {
    return null
  }

  return (
    <div className={className}>
      <div className="space-y-0.5">
        {timing.priceRow ? <p>{timing.priceRow}</p> : null}
        {timing.dateTimeRow || onViewReel ? (
          <div className="flex items-start justify-between gap-3">
            {timing.dateTimeRow ? (
              <p className="min-w-0 flex-1">{timing.dateTimeRow}</p>
            ) : (
              <span className="flex-1" aria-hidden />
            )}
            {onViewReel ? (
              <ViewReelBadge
                onClick={(e) => {
                  e.stopPropagation()
                  onViewReel()
                }}
              />
            ) : null}
          </div>
        ) : null}
      </div>
    </div>
  )
}
