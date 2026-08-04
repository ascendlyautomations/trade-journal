"use client"

import { memo } from "react"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { postImageSrc } from "@/app/components/feed/feedPostHelpers"
import { formatRR } from "@/lib/formatDisplay"
import type { ProfileTradeRow } from "./profileTypes"

type ProfileTradeGridTileProps = {
  trade: ProfileTradeRow
  onOpenTrade: (trade: ProfileTradeRow) => void
}

function formatTileMoney(value: number) {
  const abs = Math.abs(value).toLocaleString(undefined, {
    maximumFractionDigits: 0,
  })
  return value < 0 ? `-$${abs}` : `$${abs}`
}

function formatTileDate(value: string | null | undefined): string {
  if (!value) return "—"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return "—"
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  })
}

function hasUsableRr(value: unknown): boolean {
  if (value == null || value === "") return false
  const n = Number(value)
  return Number.isFinite(n)
}

function secondaryMetric(trade: ProfileTradeRow, pnl: number, pnlFinite: boolean): string {
  if (hasUsableRr(trade.rr)) {
    return `${formatRR(trade.rr)} RR`
  }

  if (pnlFinite) {
    return pnl >= 0 ? "Win" : "Loss"
  }

  const contractsRaw = (trade as { contracts?: unknown }).contracts
  const contracts = Number(contractsRaw)
  if (contractsRaw != null && contractsRaw !== "" && Number.isFinite(contracts) && contracts > 0) {
    return `${contracts} ct`
  }

  const direction =
    trade.direction != null ? String(trade.direction).trim() : ""
  if (direction) return direction

  const session = trade.session != null ? String(trade.session).trim() : ""
  if (session) return session

  return "—"
}

function ProfileTradeGridTile({
  trade,
  onOpenTrade,
}: ProfileTradeGridTileProps) {
  const imageSrc = postImageSrc(trade.image_url)
  const pnl = Number(trade.pnl)
  const pnlFinite = Number.isFinite(pnl)
  const ticker = trade.ticker != null ? String(trade.ticker).trim() || "—" : "—"
  const pnlLabel = pnlFinite
    ? `${pnl >= 0 ? "+" : ""}${formatTileMoney(pnl)}`
    : "—"
  const pnlClass = pnlFinite
    ? pnl >= 0
      ? "text-emerald-400"
      : "text-red-400"
    : "text-gray-400"
  const secondary = secondaryMetric(trade, pnl, pnlFinite)
  const dateLabel = formatTileDate(trade.created_at)

  return (
    <button
      type="button"
      onClick={() => onOpenTrade(trade)}
      aria-label={`${ticker} ${pnlLabel} ${secondary} ${dateLabel}`}
      className="group flex w-full flex-col overflow-hidden rounded-md border border-white/10 bg-white/5 text-left transition hover:border-white/25 hover:bg-white/[0.07] focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-400/60"
    >
      <div className="relative aspect-square w-full overflow-hidden bg-black/30">
        {imageSrc ? (
          <div className="absolute inset-0">
            <TradeScreenshotImage
              src={imageSrc}
              preset="feed-thumb"
              objectFit="cover"
              className="h-full w-full transition duration-300 group-hover:scale-[1.02]"
              logContext="profile-trade-grid-tile"
            />
          </div>
        ) : (
          <div
            className="flex h-full w-full items-center justify-center bg-gradient-to-br from-white/[0.08] to-white/[0.02]"
            aria-hidden
          >
            <span className="text-[10px] font-medium uppercase tracking-wider text-gray-500">
              No chart
            </span>
          </div>
        )}
        {trade.is_pinned ? (
          <span
            className="absolute left-1 top-1 text-[10px] drop-shadow"
            aria-label="Pinned"
          >
            📌
          </span>
        ) : null}
      </div>

      <div className="flex h-[40px] flex-col justify-center gap-0.5 border-t border-white/10 px-1.5 py-1">
        <div className="flex min-w-0 items-baseline justify-between gap-1">
          <span className="min-w-0 truncate text-[11px] font-medium leading-none text-white">
            {ticker}
          </span>
          <span
            className={`shrink-0 text-[11px] font-semibold leading-none tabular-nums ${pnlClass}`}
          >
            {pnlLabel}
          </span>
        </div>
        <div className="flex min-w-0 items-baseline justify-between gap-1">
          <span className="min-w-0 truncate text-[10px] leading-none text-gray-400">
            {secondary}
          </span>
          <span className="shrink-0 text-[10px] leading-none tabular-nums text-gray-400">
            {dateLabel}
          </span>
        </div>
      </div>
    </button>
  )
}

export default memo(
  ProfileTradeGridTile,
  (prev, next) =>
    prev.trade === next.trade && prev.onOpenTrade === next.onOpenTrade
)
