"use client"

import { memo } from "react"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import ExpandableText from "@/app/components/ui/ExpandableText"
import {
  formatPoints,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { resolveTradePoints } from "@/lib/resolveTradePoints"

type FeedPostBodyProps = {
  pnl: number
  pnlPositive: boolean
  tickerLabel: string
  dirLabel: string
  accountTypeNorm: string
  accountTypeStyles: string
  rr: unknown
  publicDesc: string | null
  timingTrade: Record<string, unknown> | null
  onViewReel?: () => void
}

function FeedPostBody({
  pnl,
  pnlPositive,
  tickerLabel,
  dirLabel,
  accountTypeNorm,
  accountTypeStyles,
  rr,
  publicDesc,
  timingTrade,
  onViewReel,
}: FeedPostBodyProps) {
  const resolvedPoints = resolveTradePoints(timingTrade)
  return (
    <div className="min-w-0 space-y-1.5 overflow-hidden px-4 pb-2.5 pt-0.5">
      <div className="flex min-w-0 flex-nowrap items-center justify-between gap-x-2">
        <div className="flex min-w-0 items-center gap-2 overflow-hidden md:gap-3">
          <div
            className={`shrink-0 text-base font-semibold tabular-nums md:text-lg ${
              pnlPositive ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {formatSignedPnlDisplay(pnl)}
          </div>

          <div className="flex min-w-0 items-center gap-2 overflow-hidden text-xs font-medium text-white md:text-sm">
            <span className="min-w-0 truncate">
              {tickerLabel} • {dirLabel}
            </span>
            {accountTypeNorm ? (
              <span
                className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] md:text-xs ${accountTypeStyles}`}
              >
                {accountTypeNorm}
              </span>
            ) : null}
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-2 text-xs text-gray-300 md:text-sm">
          {rr != null && rr !== "" ? (
            <span className="tabular-nums">RR {formatRR(rr)}</span>
          ) : null}
          {resolvedPoints !== null ? (
            <span className="rounded-md bg-white/10 px-2 py-0.5 text-[10px] text-gray-200 md:text-sm">
              {formatPoints(resolvedPoints)} pts
            </span>
          ) : null}
        </div>
      </div>

      {publicDesc ? (
        <ExpandableText
          className="min-w-0 text-xs leading-snug text-white md:text-sm md:leading-relaxed"
          textClassName="break-words text-white"
        >
          {publicDesc}
        </ExpandableText>
      ) : null}

      {timingTrade || onViewReel ? (
        <div className="min-w-0">
          <TradeCardTimingBlock
            trade={timingTrade ?? {}}
            onViewReel={onViewReel}
          />
        </div>
      ) : null}
    </div>
  )
}

export default memo(FeedPostBody)
