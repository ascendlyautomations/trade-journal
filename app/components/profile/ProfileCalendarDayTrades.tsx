"use client"

import "./profileCalendarDayTrades.css"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatEST } from "@/lib/formatEST"
import { formatRR, formatTradePoints } from "@/lib/formatDisplay"
import { resolveTradePoints } from "@/lib/resolveTradePoints"

export type ProfileCalendarDayTrade = {
  id: string | number
  created_at: string
  pnl: number | null
  ticker?: string | null
  direction?: string | null
  image_url?: string | null
  rr?: number | string | null
  points?: number | string | null
  entry_price?: number | string | null
  exit_price?: number | string | null
  session?: string | null
  mode?: string | null
  strategy?: string | null
}

type TradeMetaProps = {
  trade: ProfileCalendarDayTrade
  modeLower: string
  accountLineWithType: string | null
  pnl: number
  compact?: boolean
}

function TradeMetaBlock({
  trade,
  modeLower,
  accountLineWithType,
  pnl,
  compact = false,
}: TradeMetaProps) {
  const titleClass = compact
    ? "text-sm font-semibold leading-snug text-white"
    : "text-base font-semibold leading-snug text-white"
  const pnlClass = compact
    ? "shrink-0 text-sm font-bold tabular-nums sm:text-base"
    : "text-lg font-bold tabular-nums"

  return (
    <div className="min-w-0 flex-1 space-y-1.5 overflow-hidden">
      <div className="flex items-start justify-between gap-3">
        <p className={`min-w-0 ${titleClass}`}>
          <span className="break-words">{trade.ticker || "—"}</span>
          <span className="text-gray-400"> · </span>
          <span className="break-words">{trade.direction || "—"}</span>
        </p>
        <p
          className={`${pnlClass} ${
            pnl >= 0 ? "text-green-400" : "text-red-400"
          }`}
        >
          {formatPnlCurrency(pnl)}
        </p>
      </div>
      <p className="text-xs text-gray-400 sm:text-sm">
        {formatEST(trade.created_at)}
      </p>
      <div className="flex flex-wrap gap-x-2 gap-y-1 text-xs text-gray-400">
        {trade.rr != null && trade.rr !== "" ? (
          <span className="whitespace-nowrap">RR: {formatRR(trade.rr)}</span>
        ) : null}
        {resolveTradePoints(trade) !== null ? (
          <span className="whitespace-nowrap">
            Pts: {formatTradePoints(trade)}
          </span>
        ) : null}
        {trade.session ? (
          <span className="whitespace-nowrap">{trade.session}</span>
        ) : null}
        {modeLower === "backtest" ? (
          <span className="whitespace-nowrap text-blue-300/90">Backtest</span>
        ) : null}
      </div>
      {modeLower !== "backtest" && accountLineWithType ? (
        <p className="break-words text-xs text-gray-400">{accountLineWithType}</p>
      ) : null}
      {trade.strategy ? (
        <p className="break-words text-xs text-blue-400">{trade.strategy}</p>
      ) : null}
    </div>
  )
}

function TradeThumbnail({
  src,
  logContext,
  wrapperClassName = "",
}: {
  src: string
  logContext: string
  wrapperClassName?: string
}) {
  return (
    <div
      className={`relative aspect-[5/4] w-full overflow-hidden rounded-lg border border-white/10 bg-black/30 ${wrapperClassName}`}
    >
      <TradeScreenshotImage
        src={src}
        preset="trade-thumb"
        fillFrame
        objectFit="contain"
        className="h-full w-full"
        logContext={logContext}
      />
    </div>
  )
}

export function ProfileCalendarDayTradeRow({
  trade,
  imageSrc,
  modeLower,
  accountLineWithType,
  onOpen,
}: {
  trade: ProfileCalendarDayTrade
  imageSrc: string | null
  modeLower: string
  accountLineWithType: string | null
  onOpen: () => void
}) {
  const pnl = Number(trade.pnl) || 0

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onOpen()
        }
      }}
      className="tt-profile-calendar-day-trade flex cursor-pointer flex-col gap-3 overflow-hidden rounded-xl border border-white/10 bg-black/40 p-3 transition hover:bg-black/60 sm:flex-row sm:items-start sm:gap-4 sm:p-4"
    >
      {imageSrc ? (
        <div className="tt-profile-calendar-day-trade-thumb mx-auto w-full max-w-[9rem] shrink-0 sm:mx-0 sm:w-28">
          <TradeThumbnail
            src={imageSrc}
            wrapperClassName="tt-profile-calendar-day-trade-thumb"
            logContext="profile-calendar-trade-list"
          />
        </div>
      ) : null}
      <TradeMetaBlock
        trade={trade}
        modeLower={modeLower}
        accountLineWithType={accountLineWithType}
        pnl={pnl}
        compact
      />
    </div>
  )
}

export function ProfileCalendarTradeDetailModal({
  trade,
  imageSrc,
  modeLower,
  accountLineWithType,
  onClose,
}: {
  trade: ProfileCalendarDayTrade
  imageSrc: string | null
  modeLower: string
  accountLineWithType: string | null
  onClose: () => void
}) {
  const pnl = Number(trade.pnl) || 0

  return (
    <div
      className="fixed inset-0 z-[200] flex items-center justify-center bg-black/70 p-4"
      onClick={onClose}
    >
      <div
        className="tt-profile-calendar-trade-modal-panel max-h-[90vh] w-full max-w-xl overflow-x-hidden overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-4 sm:p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between gap-3">
          <p className="text-sm font-semibold text-white">Trade</p>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 text-gray-400 hover:text-white"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:gap-5">
          {imageSrc ? (
            <div className="tt-profile-calendar-trade-modal-thumb mx-auto w-full max-w-[12rem] shrink-0 sm:mx-0 sm:w-44">
              <TradeThumbnail
                src={imageSrc}
                wrapperClassName="tt-profile-calendar-trade-modal-thumb"
                logContext="profile-calendar-trade"
              />
            </div>
          ) : null}
          <TradeMetaBlock
            trade={trade}
            modeLower={modeLower}
            accountLineWithType={accountLineWithType}
            pnl={pnl}
          />
        </div>
      </div>
    </div>
  )
}
