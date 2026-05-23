"use client"

import { memo } from "react"

type FeedPostBodyProps = {
  pnl: number
  pnlPositive: boolean
  tickerLabel: string
  dirLabel: string
  accountTypeNorm: string
  accountTypeStyles: string
  rr: unknown
  points: unknown
  publicDesc: string | null
  createdAtLabel: string
}

function FeedPostBody({
  pnl,
  pnlPositive,
  tickerLabel,
  dirLabel,
  accountTypeNorm,
  accountTypeStyles,
  rr,
  points,
  publicDesc,
  createdAtLabel,
}: FeedPostBodyProps) {
  return (
    <div className="space-y-3 px-4 pb-3">
      <div className="mt-2 flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div
            className={`shrink-0 text-lg font-semibold tabular-nums ${
              pnlPositive ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {Number.isNaN(pnl) ? "—" : `${pnlPositive ? "+" : ""}$${pnl}`}
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
            <span className="tabular-nums">RR {rr}</span>
          ) : null}
          {points !== null && points !== undefined ? (
            <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
              {points} pts
            </span>
          ) : null}
        </div>
      </div>

      {publicDesc ? (
        <p className="px-1 text-sm leading-relaxed text-white">{publicDesc}</p>
      ) : null}

      <p className="text-xs text-white/40">{createdAtLabel}</p>
    </div>
  )
}

export default memo(FeedPostBody)
