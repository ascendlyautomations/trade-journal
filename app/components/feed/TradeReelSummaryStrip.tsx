"use client"

import Link from "next/link"
import { formatRR } from "@/lib/formatDisplay"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  isTradeAttachedReel,
  resolveReelTradeJoin,
  type LinkedTradeSummary,
} from "@/lib/reels"

type TradeReelSummaryStripProps = {
  post: {
    trade_id?: string | null
    trades?: LinkedTradeSummary | LinkedTradeSummary[] | null
  }
  className?: string
}

export default function TradeReelSummaryStrip({
  post,
  className = "",
}: TradeReelSummaryStripProps) {
  if (!isTradeAttachedReel(post)) return null

  const trade = resolveReelTradeJoin(post)
  if (!trade?.id) return null

  const ticker = trade.ticker?.trim() || "—"
  const direction = trade.direction?.trim() || "—"
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const pnlLabel = Number.isFinite(pnl)
    ? formatPnlCurrency(pnl)
    : "—"
  const rr =
    trade.rr != null && trade.rr !== "" ? formatRR(trade.rr) : "—"
  const outcome = Number.isFinite(pnl)
    ? pnl > 0
      ? "WIN"
      : pnl < 0
        ? "LOSS"
        : "BE"
    : null

  return (
    <div
      className={`flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-white/[0.04] px-3 py-2.5 ${className}`}
    >
      <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs sm:text-sm">
        <span className="font-medium text-white">
          {ticker} · {direction}
        </span>
        <span className="text-gray-500">·</span>
        <span
          className={
            Number.isFinite(pnl)
              ? pnl >= 0
                ? "font-semibold text-emerald-400"
                : "font-semibold text-red-400"
              : "text-gray-400"
          }
        >
          {pnlLabel}
        </span>
        <span className="text-gray-500">·</span>
        <span className="text-gray-300">RR {rr}</span>
        {outcome ? (
          <>
            <span className="text-gray-500">·</span>
            <span
              className={
                outcome === "WIN"
                  ? "text-emerald-400/90"
                  : outcome === "LOSS"
                    ? "text-red-400/90"
                    : "text-gray-400"
              }
            >
              {outcome}
            </span>
          </>
        ) : null}
      </div>
      <Link
        href={`/trade/${trade.id}`}
        onClick={(e) => e.stopPropagation()}
        className="shrink-0 text-xs font-medium text-violet-300 transition hover:text-violet-200"
      >
        View Trade →
      </Link>
    </div>
  )
}
