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
    <div className="space-y-3 px-4 pb-3">
      <div className="mt-2 flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div
            className={`shrink-0 text-lg font-semibold tabular-nums ${
              pnlPositive ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {formatSignedPnlDisplay(pnl)}
          </div>

          <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">
            <span className="truncate">
              {tickerLabel} • {dirLabel}
            </span>
            {accountTypeNorm ? (
              <span
                className={`px-2 py-0.5 text-xs rounded-full ${accountTypeStyles}`}
              >
                {accountTypeNorm}
              </span>
            ) : null}
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">
          {rr != null && rr !== "" ? (
            <span className="tabular-nums">RR {formatRR(rr)}</span>
          ) : null}
          {resolvedPoints !== null ? (
            <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
              {formatPoints(resolvedPoints)} pts
            </span>
          ) : null}
        </div>
      </div>

      {publicDesc ? (
        <ExpandableText
          className="px-1 text-sm leading-relaxed text-white"
          textClassName="text-white"
        >
          {publicDesc}
        </ExpandableText>
      ) : null}

      {timingTrade || onViewReel ? (
        <div className="px-1">
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
