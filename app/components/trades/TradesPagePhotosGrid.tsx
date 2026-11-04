"use client"

import { memo } from "react"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { formatMoneyUnknown } from "@/lib/formatDisplay"
import { formatEST } from "@/lib/formatEST"
import type { TradesPagePhotoGridEntry } from "@/lib/tradesPagePhotosGrid"

type TradesPagePhotosGridProps = {
  entries: TradesPagePhotoGridEntry[]
  selectedTradeId?: string | null
  onOpenTrade: (trade: Record<string, unknown>) => void
}

function formatTileDate(trade: Record<string, unknown>): string {
  const raw =
    (trade.created_at as string | undefined) ??
    (trade.trade_date as string | undefined) ??
    ""
  if (!raw) return "—"
  const formatted = formatEST(String(raw))
  return formatted || "—"
}

function TradesPagePhotosGrid({
  entries,
  selectedTradeId = null,
  onOpenTrade,
}: TradesPagePhotosGridProps) {
  return (
    <div className="grid grid-cols-3 gap-1 md:gap-1.5">
      {entries.map(({ key, trade, previewUrl, imageUrls }, index) => {
        const tradeId = String(trade.id ?? "")
        const isSelected = selectedTradeId === tradeId
        const ticker =
          trade.ticker != null ? String(trade.ticker).trim() || "—" : "—"
        const pnl = Number(trade.pnl)
        const pnlLabel = Number.isFinite(pnl)
          ? formatMoneyUnknown(pnl)
          : "—"
        const pnlClass = Number.isFinite(pnl)
          ? pnl >= 0
            ? "text-emerald-300"
            : "text-red-300"
          : "text-gray-200"
        const dateLabel = formatTileDate(trade)
        const multi = imageUrls.length > 1

        return (
          <div
            key={key}
            id={tradeId ? `trade-${tradeId}` : undefined}
            className={
              isSelected ? "rounded-sm ring-2 ring-blue-400/80" : undefined
            }
          >
            <button
              type="button"
              onClick={() => onOpenTrade(trade)}
              aria-label={`${ticker}, P&L ${pnlLabel}, ${dateLabel}`}
              className="group relative block aspect-square w-full overflow-hidden bg-black/40 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-400/70"
            >
              <TradeScreenshotImage
                src={previewUrl}
                preset="feed-thumb"
                objectFit="cover"
                className="absolute inset-0 h-full w-full transition duration-300 group-hover:scale-[1.03]"
                logContext="trades-page-photos-grid"
                priority={index < 6}
              />
              {multi ? (
                <span
                  className="absolute right-1.5 top-1.5 rounded bg-black/55 px-1.5 py-0.5 text-[10px] font-semibold text-white backdrop-blur-sm"
                  aria-hidden
                >
                  {imageUrls.length}
                </span>
              ) : null}
              <div
                className="pointer-events-none absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/75 via-black/35 to-transparent p-2 opacity-0 transition-opacity duration-200 group-hover:opacity-100"
                aria-hidden
              >
                <p className="truncate text-sm font-semibold leading-tight text-white">
                  {ticker}
                </p>
                <div className="mt-0.5 flex items-baseline justify-between gap-2">
                  <span
                    className={`text-xs font-semibold tabular-nums ${pnlClass}`}
                  >
                    {pnlLabel}
                  </span>
                  <span className="shrink-0 text-[10px] tabular-nums text-gray-300">
                    {dateLabel}
                  </span>
                </div>
              </div>
            </button>
          </div>
        )
      })}
    </div>
  )
}

export function TradesPagePhotosGridSkeleton() {
  return (
    <div
      aria-busy="true"
      aria-label="Loading trade screenshots"
      className="grid grid-cols-3 gap-1 md:gap-1.5"
    >
      {Array.from({ length: 9 }).map((_, i) => (
        <div
          key={i}
          className="aspect-square animate-pulse bg-white/10"
        />
      ))}
    </div>
  )
}

export default memo(TradesPagePhotosGrid)
