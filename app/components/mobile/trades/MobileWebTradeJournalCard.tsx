"use client"

import { memo, useEffect, useMemo, useState, type MouseEvent } from "react"
import DropdownMenu from "@/app/components/ui/DropdownMenu"
import { formatShortDateTimeEST } from "@/lib/formatDate"
import { formatMoneyUnknown, formatNumberUnknown } from "@/lib/formatDisplay"
import {
  hasMobileWebTradeScreenshot,
  mobileWebJournalPointsLabel,
  mobileWebJournalRrLabel,
  MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX,
  MOBILE_WEB_TRADE_THUMB_WIDTH_PX,
  mobileWebTradeThumbHeightPx,
} from "@/lib/mobileWebTradesPresentation"
import { phoneWebThumbnailSrc } from "@/lib/mobileWebMedia"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import { formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"
import { resolveTradeDurationLabel } from "@/lib/tradeTimingDisplay"
import { Globe, Lock, MoreHorizontal } from "lucide-react"
import type { CopyTradeWireRow } from "@/lib/copyTradePresentation"

type MobileWebTradeJournalCardProps = {
  trade: any
  copyGroupMembers?: readonly CopyTradeWireRow[]
  copyModeSummary?: string | null
  accountRow?: any | null
  selected?: boolean
  onOpen: (trade: any) => void
  onEdit: (trade: any) => void
  onDelete: (tradeId: string) => void
  onSendClick: (trade: any) => void
  onAnalyze?: (trade: any) => void
  onImageClick: (imageUrl: string) => void
}

const LABEL = "text-[color:var(--tt-text-tertiary,#a8b3c2)]"
const VALUE = "text-[color:var(--tt-text,#f0f3f6)]"
const MUTED = "text-[color:var(--tt-text-muted,#c0cad6)]"

function resolveSide(trade: any): "Long" | "Short" | "Unknown" {
  const raw = String(trade.direction ?? trade.side ?? "").trim()
  if (/^long$/i.test(raw)) return "Long"
  if (/^short$/i.test(raw)) return "Short"
  const entry = Number(trade.entry_price ?? trade.entry)
  const exit = Number(trade.exit_price ?? trade.exit)
  if (Number.isFinite(entry) && Number.isFinite(exit) && exit !== entry) {
    return exit > entry ? "Long" : "Short"
  }
  return "Unknown"
}

function MobileWebTradeJournalCard({
  trade,
  copyGroupMembers,
  copyModeSummary,
  accountRow = null,
  selected = false,
  onOpen,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
}: MobileWebTradeJournalCardProps) {
  const ticker = String(trade.ticker ?? "").trim() || "—"
  const side = resolveSide(trade)
  const pnl = Number(trade.pnl)
  const pnlPositive = Number.isFinite(pnl) ? pnl >= 0 : true
  const entryPrice = trade.entry_price ?? trade.entry ?? null
  const exitPrice = trade.exit_price ?? trade.exit ?? null
  const contracts = trade.contracts ?? trade.quantity ?? trade.size ?? null
  const screenshotUrl = useMemo(
    () => tradeScreenshotPublicUrl(trade.image_url),
    [trade.image_url]
  )
  const [thumbFailed, setThumbFailed] = useState(false)
  const [thumbHeight, setThumbHeight] = useState<number | null>(null)
  const [thumbSrc, setThumbSrc] = useState<string | null>(null)
  useEffect(() => {
    setThumbFailed(false)
    setThumbHeight(null)
    setThumbSrc(screenshotUrl ? phoneWebThumbnailSrc(screenshotUrl, 256) : null)
  }, [screenshotUrl])
  const showThumb =
    hasMobileWebTradeScreenshot(screenshotUrl) && !thumbFailed
  const accountLine = useMemo(
    () => formatTradeAccountNameSizeLine(trade, accountRow),
    [accountRow, trade]
  )
  const dateLine =
    formatShortDateTimeEST(trade.entry_time || trade.created_at || trade.trade_date) ||
    "—"
  const duration = resolveTradeDurationLabel(trade) ?? "—"
  const rrLabel = mobileWebJournalRrLabel(trade.rr) ?? "—"
  const pointsLabel = mobileWebJournalPointsLabel(trade) ?? "—"
  const isCopyGroup = Boolean(copyGroupMembers && copyGroupMembers.length > 1)
  const isPublic = trade.is_public === true

  function handleOpen() {
    onOpen(trade)
  }

  function handleThumbClick(event: MouseEvent) {
    event.stopPropagation()
    if (screenshotUrl) onImageClick(screenshotUrl)
  }

  return (
    <article
      className={`relative rounded-[18px] border bg-white/5 p-3 ${
        selected ? "border-blue-400/80" : "border-white/10"
      }`}
    >
      <button
        type="button"
        onClick={handleOpen}
        className="flex min-h-0 w-full flex-col gap-2 text-left"
      >
        <div className="flex items-baseline gap-2 pr-10">
          <div className="min-w-0 flex-1">
            <p className={`truncate text-[17px] font-semibold leading-tight tracking-tight ${VALUE}`}>
              {ticker}
            </p>
            <p
              className={`text-[11px] font-semibold uppercase leading-tight tracking-wide ${
                side === "Long"
                  ? "text-emerald-400"
                  : side === "Short"
                    ? "text-red-400"
                    : LABEL
              }`}
            >
              {side === "Unknown" ? "—" : side}
            </p>
          </div>
          <p
            className={`max-w-[45%] shrink-0 truncate text-right text-[17px] font-semibold leading-tight tabular-nums ${
              pnlPositive ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {formatMoneyUnknown(trade.pnl, { empty: "—" })}
          </p>
        </div>

        <div className="flex items-start gap-3">
          <div className="min-w-0 flex-1">
            {isCopyGroup ? (
              <>
                <p className={`text-[12px] font-semibold leading-snug ${VALUE}`}>
                  Copy Traded
                </p>
                {copyModeSummary ? (
                  <p className={`line-clamp-2 text-[12px] leading-snug ${MUTED}`}>
                    {copyModeSummary}
                  </p>
                ) : null}
              </>
            ) : (
              <p className={`truncate text-[12px] leading-snug ${MUTED}`}>
                {accountLine || "—"}
              </p>
            )}
            <p className={`truncate text-[12px] leading-snug ${MUTED}`}>
              {dateLine}
            </p>
          </div>
          {showThumb && screenshotUrl ? (
            <div
              role="presentation"
              onClick={handleThumbClick}
              className="relative shrink-0 overflow-hidden rounded-[14px] bg-white/10"
              style={{
                width: MOBILE_WEB_TRADE_THUMB_WIDTH_PX,
                height: thumbHeight ?? MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX,
              }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={thumbSrc ?? screenshotUrl}
                alt=""
                width={MOBILE_WEB_TRADE_THUMB_WIDTH_PX}
                height={thumbHeight ?? MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX}
                loading="lazy"
                decoding="async"
                className="block h-full w-full object-cover object-center"
                onError={() => {
                  if (screenshotUrl && thumbSrc !== screenshotUrl) {
                    setThumbSrc(screenshotUrl)
                    return
                  }
                  setThumbFailed(true)
                }}
                onLoad={(event) => {
                  setThumbHeight(
                    mobileWebTradeThumbHeightPx(
                      event.currentTarget.naturalWidth,
                      event.currentTarget.naturalHeight
                    )
                  )
                }}
              />
            </div>
          ) : hasMobileWebTradeScreenshot(screenshotUrl) && thumbFailed ? (
            <div
              className="tt-mobile-web-media-unavailable flex shrink-0 items-center justify-center rounded-[14px] border border-white/10 bg-white/5 text-center text-[10px] font-medium leading-tight text-[color:var(--tt-text-tertiary,#a8b3c2)]"
              style={{
                width: MOBILE_WEB_TRADE_THUMB_WIDTH_PX,
                minHeight: MOBILE_WEB_TRADE_THUMB_MIN_HEIGHT_PX,
              }}
            >
              Image unavailable
            </div>
          ) : null}
        </div>

        <div className="grid grid-cols-3 gap-2">
          <JournalField
            label="Entry"
            value={formatMoneyUnknown(entryPrice, { empty: "—" })}
          />
          <JournalField
            label="Exit"
            value={formatMoneyUnknown(exitPrice, { empty: "—" })}
          />
          <JournalField
            label="Contracts"
            value={formatNumberUnknown(contracts, "—")}
          />
        </div>

        <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5 text-[11px]">
          <JournalInlineMetric label="Duration" value={duration} />
          <JournalInlineMetric label="R:R" value={rrLabel} />
          <JournalInlineMetric label="Points" value={pointsLabel} />
          <span className={`ml-auto inline-flex shrink-0 items-center gap-0.5 ${LABEL}`}>
            {isPublic ? (
              <Globe className="h-3 w-3" strokeWidth={2} aria-hidden />
            ) : (
              <Lock className="h-3 w-3" strokeWidth={2} aria-hidden />
            )}
            {isPublic ? "Public" : "Private"}
          </span>
        </div>
      </button>

      <div className="absolute right-0.5 top-0.5 z-[1]">
        <DropdownMenu
          align="right"
          stopPropagation
          trigger={
            <span className={`inline-flex h-11 w-11 items-center justify-center rounded-full ${LABEL}`}>
              <MoreHorizontal className="h-5 w-5" strokeWidth={2} aria-hidden />
              <span className="sr-only">Trade actions</span>
            </span>
          }
          items={[
            { id: "open", label: "Open", onSelect: handleOpen },
            { id: "edit", label: "Edit", onSelect: () => onEdit(trade) },
            ...(onAnalyze
              ? [
                  {
                    id: "analyze",
                    label: "Analyze",
                    onSelect: () => onAnalyze(trade),
                  },
                ]
              : []),
            {
              id: "share",
              label: "Share",
              onSelect: () => onSendClick(trade),
            },
            {
              id: "delete",
              label: "Delete",
              variant: "danger" as const,
              onSelect: () => onDelete(String(trade.id ?? "")),
            },
          ]}
        />
      </div>
    </article>
  )
}

function JournalField({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <p className={`text-[10px] leading-tight ${LABEL}`}>{label}</p>
      <p className={`truncate text-[13px] font-medium leading-tight tabular-nums ${VALUE}`}>
        {value}
      </p>
    </div>
  )
}

function JournalInlineMetric({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <span className={`shrink-0 ${LABEL}`}>
      {label}{" "}
      <span className={`font-medium tabular-nums ${VALUE}`}>{value}</span>
    </span>
  )
}

export default memo(MobileWebTradeJournalCard)
