"use client"

import { getCopiedAccountCount, isCopyTradedMode } from "@/lib/tradeMode"

type CopyTradedBadgeProps = {
  className?: string
  /** Destination account count; when omitted, derived from `trade` if provided. */
  count?: number
  trade?: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: unknown
  } | null
}

export default function CopyTradedBadge({
  className = "",
  count,
  trade,
}: CopyTradedBadgeProps) {
  const resolvedCount =
    count != null
      ? Math.max(0, Math.floor(count))
      : trade
        ? getCopiedAccountCount(trade)
        : 0

  if (trade && !isCopyTradedMode(trade) && count == null) return null

  const label =
    resolvedCount > 0 ? `Copy Traded ×${resolvedCount}` : "Copy Traded"

  return (
    <span
      className={`rounded bg-violet-500/15 px-2 py-0.5 text-[11px] font-medium text-violet-200 ${className}`}
    >
      {label}
    </span>
  )
}
