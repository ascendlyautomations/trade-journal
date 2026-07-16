"use client"

import { formatMoneyUnknown } from "@/lib/formatDisplay"
import { SITE_NAME } from "@/lib/site"

/** Half-scale design canvases — export at pixelRatio 2 → 1080px wide. */
export const TRADE_SHARE_V2_SQUARE_SIZE = { width: 540, height: 540 } as const
export const TRADE_SHARE_V2_STORY_SIZE = { width: 540, height: 960 } as const

export type TradeShareCardV2Variant = "square" | "story"

export type TradeShareCardV2Trade = {
  ticker?: string | null
  pnl?: number | string | null
  rr?: number | string | null
  direction?: string | null
  entry_price?: number | null
  exit_price?: number | null
  /** Shown as trade date line */
  exit_time?: string | null
  trade_date?: string | null
  date?: string | null
  entry_time?: string | null
}

export type TradeShareCardV2Profile = {
  username?: string | null
}

export type TradeShareCardV2Props = {
  trade: TradeShareCardV2Trade
  profile?: TradeShareCardV2Profile | null
  variant?: TradeShareCardV2Variant
  /** Optional id for future export wiring — unused in preview. */
  exportId?: string
}

function directionLabel(trade: TradeShareCardV2Trade): string {
  if (trade.direction?.trim()) return trade.direction.trim()
  if (trade.exit_price != null && trade.entry_price != null) {
    return trade.exit_price > trade.entry_price ? "Long" : "Short"
  }
  return "Long"
}

function formatRr(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—"
  const n = Number(value)
  if (!Number.isFinite(n)) return "—"
  const formatted = n.toLocaleString(undefined, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 2,
  })
  return `${formatted}R`
}

function parseDateLike(value: unknown): Date | null {
  if (value === null || value === undefined || value === "") return null
  const raw = String(value).trim()
  if (!raw) return null
  const parsed = new Date(raw)
  if (!Number.isNaN(parsed.getTime())) return parsed
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const dateOnly = new Date(`${raw}T12:00:00Z`)
    if (!Number.isNaN(dateOnly.getTime())) return dateOnly
  }
  return null
}

function formatShareDate(trade: TradeShareCardV2Trade): string {
  const source =
    trade.exit_time ??
    trade.trade_date ??
    trade.date ??
    trade.entry_time ??
    null
  const date = parseDateLike(source)
  if (!date) return "—"
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "America/New_York",
  })
}

function normalizeUsername(profile: TradeShareCardV2Profile | null | undefined): string {
  const raw = profile?.username != null ? String(profile.username).trim() : ""
  if (!raw) return "trader"
  return raw.replace(/^@+/, "")
}

type DirectionTone = "long" | "short" | "neutral"

function directionTone(dir: string): DirectionTone {
  const lower = dir.toLowerCase()
  if (lower === "long") return "long"
  if (lower === "short") return "short"
  return "neutral"
}

const FONT_STACK =
  'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif'

export default function TradeShareCardV2({
  trade,
  profile = null,
  variant = "story",
  exportId,
}: TradeShareCardV2Props) {
  const size =
    variant === "square" ? TRADE_SHARE_V2_SQUARE_SIZE : TRADE_SHARE_V2_STORY_SIZE
  const isStory = variant === "story"

  const pnl = Number(trade.pnl)
  const hasPnl = Number.isFinite(pnl)
  const positive = hasPnl && pnl >= 0
  const negative = hasPnl && pnl < 0

  const dir = directionLabel(trade)
  const tone = directionTone(dir)
  const username = normalizeUsername(profile)
  const ticker = trade.ticker?.trim() || "—"
  const rrDisplay = formatRr(trade.rr)
  const dateDisplay = formatShareDate(trade)

  const pnlColor = !hasPnl
    ? "#d1d5db"
    : positive
      ? "#6ee7b7"
      : "#fca5a5"

  const background = negative
    ? "linear-gradient(165deg, #061427 0%, #1a1030 42%, #3d1528 100%)"
    : positive
      ? "linear-gradient(165deg, #061427 0%, #0a2f3d 45%, #0f4a3a 100%)"
      : "linear-gradient(165deg, #061427 0%, #0b2d55 55%, #0f4a62 100%)"

  const accentGlow = negative
    ? "radial-gradient(ellipse 80% 50% at 50% 38%, rgba(248,113,113,0.14) 0%, transparent 70%)"
    : positive
      ? "radial-gradient(ellipse 80% 50% at 50% 38%, rgba(52,211,153,0.16) 0%, transparent 70%)"
      : "radial-gradient(ellipse 80% 50% at 50% 38%, rgba(34,211,238,0.12) 0%, transparent 70%)"

  const pillClass =
    tone === "long"
      ? "border-emerald-400/45 bg-emerald-500/20 text-emerald-200"
      : tone === "short"
        ? "border-red-400/45 bg-red-500/20 text-red-200"
        : "border-cyan-400/35 bg-cyan-500/15 text-cyan-100"

  const symbolSize = isStory ? 96 : 72
  const pnlSize = isStory ? 112 : 80
  const rrSize = isStory ? 44 : 36
  const padX = isStory ? 48 : 40
  const padY = isStory ? 56 : 40

  return (
    <div
      id={exportId}
      className="relative shrink-0 overflow-hidden"
      style={{
        width: size.width,
        height: size.height,
        fontFamily: FONT_STACK,
        background,
      }}
    >
      <div
        className="pointer-events-none absolute inset-0"
        style={{ background: accentGlow }}
      />

      <div
        className="relative flex h-full flex-col"
        style={{ padding: `${padY}px ${padX}px` }}
      >
        {/* Top — identity + direction */}
        <div className="flex shrink-0 items-center justify-between gap-4">
          <p
            className="min-w-0 truncate font-semibold text-white/90"
            style={{ fontSize: isStory ? 22 : 20 }}
          >
            @{username}
          </p>
          <span
            className={`shrink-0 rounded-full border px-4 py-1.5 font-bold uppercase tracking-wide ${pillClass}`}
            style={{ fontSize: isStory ? 14 : 13 }}
          >
            {dir}
          </span>
        </div>

        {/* Hero — symbol + P&L + RR + date */}
        <div
          className={`flex flex-1 flex-col items-center justify-center text-center ${
            isStory ? "gap-6 py-8" : "gap-4 py-2"
          }`}
        >
          <p
            className="max-w-full truncate font-black leading-none tracking-tight text-white"
            style={{ fontSize: symbolSize }}
          >
            {ticker}
          </p>

          <p
            className="font-black tabular-nums leading-none tracking-tight"
            style={{ fontSize: pnlSize, color: pnlColor }}
          >
            {formatMoneyUnknown(trade.pnl, { empty: "—" })}
          </p>

          <div className="flex flex-col items-center gap-2">
            <p
              className="font-bold tabular-nums text-white/95"
              style={{ fontSize: rrSize }}
            >
              <span className="font-semibold text-gray-400">RR </span>
              {rrDisplay}
            </p>
            <p
              className="font-medium text-gray-400"
              style={{ fontSize: isStory ? 18 : 16 }}
            >
              {dateDisplay}
            </p>
          </div>
        </div>

        {/* Footer — branding */}
        <div
          className={`flex shrink-0 items-center gap-3 border-t border-white/10 ${
            isStory ? "pt-6" : "pt-4"
          }`}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/logo.png"
            alt=""
            width={isStory ? 44 : 36}
            height={isStory ? 44 : 36}
            className="shrink-0 rounded-lg object-contain"
          />
          <div className="min-w-0 text-left">
            <p
              className="font-black leading-none tracking-tight text-white"
              style={{ fontSize: isStory ? 24 : 20 }}
            >
              {SITE_NAME}
            </p>
            <p
              className="mt-1 font-medium uppercase tracking-[0.2em] text-gray-400"
              style={{ fontSize: isStory ? 11 : 10 }}
            >
              Journal · Review · Improve
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
