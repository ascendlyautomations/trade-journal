"use client"

import { useEffect, useState, type MutableRefObject } from "react"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import { formatRR } from "@/lib/formatDisplay"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  isTradeAttachedReel,
  resolveReelTradeJoin,
  type LinkedTradeSummary,
} from "@/lib/reels"

type TradeReelSummaryStripProps = {
  post: {
    id?: string | number | null
    trade_id?: string | null
    trades?: LinkedTradeSummary | LinkedTradeSummary[] | null
  }
  viewerUserId?: string | null
  className?: string
  openTradeRef?: MutableRefObject<Record<string, boolean>>
  tradeExpandSignal?: number
}

export default function TradeReelSummaryStrip({
  post,
  viewerUserId = null,
  className = "",
  openTradeRef,
  tradeExpandSignal = 0,
}: TradeReelSummaryStripProps) {
  const reelId = post.id != null ? String(post.id) : ""
  const [tradeExpanded, setTradeExpanded] = useState(
    () => Boolean(reelId && openTradeRef?.current[reelId])
  )
  const [tradePanelMounted, setTradePanelMounted] = useState(
    () => Boolean(reelId && openTradeRef?.current[reelId])
  )

  useEffect(() => {
    if (!reelId || !openTradeRef?.current[reelId]) return
    setTradeExpanded(true)
    setTradePanelMounted(true)
    openTradeRef.current[reelId] = false
  }, [openTradeRef, reelId, tradeExpandSignal])

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

  const toggleTradePanel = () => {
    setTradeExpanded((prev) => {
      const next = !prev
      if (next) setTradePanelMounted(true)
      return next
    })
  }

  return (
    <div className={`space-y-0 ${className}`}>
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-white/[0.04] px-3 py-2.5">
        <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs sm:text-sm">
          <span className="font-medium text-white">
            {ticker} · {direction}
          </span>
          <span className="text-gray-400">·</span>
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
          <span className="text-gray-400">·</span>
          <span className="text-gray-300">RR {rr}</span>
          {outcome ? (
            <>
              <span className="text-gray-400">·</span>
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
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            toggleTradePanel()
          }}
          className="shrink-0 text-xs font-medium text-violet-300 transition hover:text-violet-200"
        >
          {tradeExpanded ? "▼ Hide Trade" : "▶ View Trade"}
        </button>
      </div>

      {tradePanelMounted ? (
        <div
          className={`grid transition-[grid-template-rows] duration-300 ease-out ${
            tradeExpanded ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
          }`}
        >
          <div className="min-h-0 overflow-hidden">
            <div className="pt-3">
              <SharedTradeMessageCard
                tradeId={String(trade.id)}
                viewerUserId={viewerUserId}
                onViewTrade={() => {}}
                hideViewTradeAction
                className="w-full"
              />
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
