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
  className = "text-[11px] leading-snug text-gray-400 md:text-xs md:leading-normal",
  onViewReel,
}: TradeCardTimingBlockProps) {
  const timing = useMemo(() => buildTradeTimingPresentation(trade), [trade])

  if (!timing.priceRow && !timing.dateTimeRow && !onViewReel) {
    return null
  }

  return (
    <div className={`min-w-0 overflow-hidden ${className}`.trim()}>
      <div className="min-w-0 space-y-0">
        {timing.priceRow ? (
          <p className="min-w-0 break-words">{timing.priceRow}</p>
        ) : null}
        {timing.dateTimeRow || onViewReel ? (
          <div className="flex min-w-0 items-start justify-between gap-3">
            {timing.dateTimeRow ? (
              <p className="min-w-0 flex-1 break-words">{timing.dateTimeRow}</p>
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
