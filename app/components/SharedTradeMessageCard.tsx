"use client"

import { useEffect, useState, type ReactNode } from "react"
import TradeSocialLayer from "@/app/components/TradeSocialLayer"
import {
  formatPoints,
  formatRR,
  formatSignedPnlDisplay,
  formatTradePoints,
} from "@/lib/formatDisplay"
import { formatPostedTimestamp } from "@/lib/formatRelativeTime"
import {
  PUBLIC_TRADE_SELECT,
  TRADES_APP_SELECT,
  sanitizeTradeForViewer,
} from "@/lib/publicAccountPrivacy"
import { SHARED_TRADE_UNAVAILABLE } from "@/lib/sharedContentNavigation"
import { supabase } from "@/lib/supabaseClient"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import ExpandableText from "@/app/components/ui/ExpandableText"

function tradeScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export type SharedTradeMessageCardProps = {
  tradeId: string | null | undefined
  viewerUserId?: string | null
  onViewTrade: (trade: { id?: string | null }) => void
  showSocialLayer?: boolean
  beforeCardContent?: ReactNode
  className?: string
  /** DM layout: full bubble width, contain screenshot aspect ratio. */
  layout?: "default" | "dm"
  /** Cached trade snapshot — renders immediately without a loading state. */
  initialTrade?: any | null
  onTradeLoaded?: (trade: any | null) => void
  /** Hide footer View trade CTA (e.g. inline expand in reel viewer). */
  hideViewTradeAction?: boolean
}

/**
 * Shared trade preview + View button used in DMs and Trade Rooms.
 * Fetches with public privacy rules; owners receive full trade fields.
 */
export default function SharedTradeMessageCard({
  tradeId,
  viewerUserId,
  onViewTrade,
  showSocialLayer = true,
  beforeCardContent,
  className,
  layout = "default",
  initialTrade = null,
  onTradeLoaded,
  hideViewTradeAction = false,
}: SharedTradeMessageCardProps) {
  const resolvedClassName =
    className ??
    (layout === "dm"
      ? "w-full max-w-[min(100%,22rem)]"
      : "w-full min-w-[15rem] max-w-[min(100%,19.5rem)]")
  const [trade, setTrade] = useState<any>(initialTrade)
  const [tradeLoading, setTradeLoading] = useState(
    () => !initialTrade && Boolean(tradeId != null && String(tradeId).trim())
  )
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)

  const resolvedTradeId = tradeId != null ? String(tradeId).trim() : ""

  useEffect(() => {
    if (!resolvedTradeId) {
      setTrade(null)
      setTradeLoading(false)
      return
    }

    let cancelled = false
    if (!initialTrade) {
      setTradeLoading(true)
      setTrade(null)
    }

    void (async () => {
      const { data } = await supabase
        .from("trades")
        .select(PUBLIC_TRADE_SELECT)
        .eq("id", resolvedTradeId)
        .maybeSingle()

      if (cancelled) return

      const isOwner =
        viewerUserId != null &&
        data?.user_id != null &&
        data.user_id === viewerUserId

      let resolved = data
      if (isOwner) {
        const { data: full } = await supabase
          .from("trades")
          .select(TRADES_APP_SELECT)
          .eq("id", resolvedTradeId)
          .maybeSingle()
        resolved = full ?? data
      }

      const sanitized = resolved
        ? sanitizeTradeForViewer(resolved, { isOwner: !!isOwner })
        : null

      setTrade(sanitized)
      setTradeLoading(false)
      onTradeLoaded?.(sanitized)
    })()

    return () => {
      cancelled = true
    }
  }, [resolvedTradeId, viewerUserId, onTradeLoaded])

  if (!resolvedTradeId) {
    return (
      <div
        className={`${resolvedClassName} rounded-lg bg-[#1e293b] p-3 text-sm italic text-gray-400`}
      >
        {SHARED_TRADE_UNAVAILABLE}
      </div>
    )
  }

  if (tradeLoading) {
    return (
      <div className={`${resolvedClassName} rounded-lg bg-[#1e293b] p-3 text-sm text-gray-400`}>
        Loading trade…
      </div>
    )
  }

  if (!trade) {
    return (
      <div
        className={`${resolvedClassName} rounded-lg bg-[#1e293b] p-3 text-sm italic text-gray-400`}
      >
        {SHARED_TRADE_UNAVAILABLE}
      </div>
    )
  }

  const imgSrc = tradeScreenshotSrc(trade.image_url)
  const pnlNum = Number(trade.pnl)
  const pnlNonNeg = !Number.isNaN(pnlNum) && pnlNum >= 0
  const directionRaw =
    trade.direction != null ? String(trade.direction).trim() : ""
  const directionLabel = directionRaw
    ? directionRaw.charAt(0).toUpperCase() + directionRaw.slice(1).toLowerCase()
    : ""

  return (
    <div className={resolvedClassName}>
      <div className="w-full rounded-xl border border-gray-700/80 bg-gradient-to-br from-[#0f172a] to-[#1e293b] p-3.5 shadow-md">
        {beforeCardContent}
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-lg font-bold tracking-tight text-white">
              {trade.ticker}
            </p>
            {trade.created_at ? (
              <time
                dateTime={String(trade.created_at)}
                className="text-[10px] text-gray-400"
              >
                {formatPostedTimestamp(trade.created_at)}
              </time>
            ) : null}
          </div>
          <p
            className={`shrink-0 text-base font-semibold tabular-nums ${
              pnlNonNeg ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {formatSignedPnlDisplay(trade.pnl)}
          </p>
        </div>

        {directionLabel ? (
          <p className="mt-1 text-xs font-medium text-gray-400">{directionLabel}</p>
        ) : null}

        <div className="mt-2 flex items-center justify-between gap-3 text-xs text-gray-400">
          <span className="tabular-nums">RR: {formatRR(trade.rr)}</span>
          <span className="tabular-nums">Points: {formatTradePoints(trade)}</span>
        </div>

        {trade.public_description ? (
          <ExpandableText
            className="mt-2 text-xs leading-snug text-gray-300"
            textClassName="text-gray-300"
            stopPropagation
          >
            {trade.public_description}
          </ExpandableText>
        ) : null}

        {imgSrc ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              setLightboxImageUrl(imgSrc)
            }}
            className="mt-2 block w-full cursor-zoom-in"
            aria-label="View trade screenshot full screen"
          >
            {layout === "dm" ? (
              <TradeScreenshotImage
                src={imgSrc}
                maxHeightPx={360}
                className="rounded-lg border border-gray-700"
                logContext="shared-trade-dm"
              />
            ) : (
              <TradeScreenshotImage
                src={imgSrc}
                maxHeightPx={112}
                className="rounded-lg border border-gray-700"
                logContext="shared-trade-card"
              />
            )}
          </button>
        ) : null}

        {hideViewTradeAction ? null : (
          <>
            <p className="mt-2.5 border-t border-gray-700/40 pt-2 text-center text-[10px] font-medium uppercase tracking-wide text-gray-400">
              Shared Trade
            </p>

            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onViewTrade(trade)
              }}
              className="mt-2.5 w-full rounded-lg border border-blue-500/30 bg-blue-500/10 px-3 py-2 text-xs font-medium text-blue-300 transition hover:bg-blue-500/20 hover:text-blue-200"
            >
              View trade →
            </button>
          </>
        )}
      </div>

      {showSocialLayer ? (
        <div className="mt-3 max-w-full" onClick={(e) => e.stopPropagation()}>
          <TradeSocialLayer
            tradeId={trade.id}
            currentUserId={viewerUserId ?? undefined}
            tradeOwnerUserId={trade.user_id}
            suppressNotifications
          />
        </div>
      ) : null}

      <ImageLightbox
        open={lightboxImageUrl != null}
        imageUrl={lightboxImageUrl}
        onClose={() => setLightboxImageUrl(null)}
      />
    </div>
  )
}
