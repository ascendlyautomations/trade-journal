"use client"

import { useMemo } from "react"
import { buildTradeTimingPresentation } from "@/lib/tradeTimingDisplay"

type TradeCardTimingBlockProps = {
  trade: Parameters<typeof buildTradeTimingPresentation>[0]
  className?: string
}

export default function TradeCardTimingBlock({
  trade,
  className = "text-xs text-gray-400",
}: TradeCardTimingBlockProps) {
  const timing = useMemo(() => buildTradeTimingPresentation(trade), [trade])

  if (!timing.priceRow && !timing.dateTimeRow) {
    return null
  }

  return (
    <div className={className}>
      <div className="space-y-0.5">
        {timing.priceRow ? <p>{timing.priceRow}</p> : null}
        {timing.dateTimeRow ? <p>{timing.dateTimeRow}</p> : null}
      </div>
    </div>
  )
}
