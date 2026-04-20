"use client"

import { forwardRef } from "react"
import { formatEST } from "@/lib/formatEST"

export type TradeShareCardProps = {
  trade: any
  /** For html-to-image: target this id with `document.getElementById` */
  exportId?: string
  profile?: { referral_code?: string | null } | null
}

function resolveScreenshotUrl(trade: any): string | null {
  const raw = trade?.image_url != null ? String(trade.image_url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function formatMoney(value: unknown): string {
  if (value === null || value === undefined) return "—"
  const number = Number(value)
  if (Number.isNaN(number)) return "—"
  return number < 0
    ? `-$${Math.abs(number).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${number.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function formatNumber(value: unknown): string {
  if (value === null || value === undefined) return "—"
  const number = Number(value)
  if (Number.isNaN(number)) return "—"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

function directionLabel(trade: any): string {
  return (
    trade.direction ||
    (trade.exit_price != null && trade.entry_price != null
      ? trade.exit_price > trade.entry_price
        ? "Long"
        : "Short"
      : "Unknown")
  )
}

/** Responsive export card — premium glass layout */
const TradeShareCard = forwardRef<HTMLDivElement, TradeShareCardProps>(
  function TradeShareCard({ trade, exportId, profile }, ref) {
    const screenshotUrl = resolveScreenshotUrl(trade)
    const pnl = Number(trade.pnl)
    const hasPnl = Number.isFinite(pnl)
    const positive = hasPnl && pnl >= 0
    const dir = directionLabel(trade)
    const dirLower = String(dir).toLowerCase()
    const longShort =
      dirLower === "long"
        ? "long"
        : dirLower === "short"
          ? "short"
          : "neutral"

    const contracts =
      trade.contracts != null && trade.contracts !== ""
        ? Number(trade.contracts).toLocaleString()
        : "—"

    const session =
      trade.session != null && String(trade.session).trim() !== ""
        ? String(trade.session)
        : "—"

    const points =
      trade.points != null && trade.points !== ""
        ? formatNumber(trade.points)
        : "—"

    const dateStr =
      trade.created_at != null
        ? formatEST(trade.created_at)
        : ""

    const codeTrim =
      profile?.referral_code != null &&
      String(profile.referral_code).trim() !== ""
        ? String(profile.referral_code).trim()
        : null

    return (
      <div className="mx-auto box-border w-full max-w-[640px] border border-red-500">
        <div
          ref={ref}
          id={exportId}
          className="w-full overflow-hidden rounded-3xl bg-gradient-to-br from-[#0b1a2a] via-[#123c4a] to-[#1c7f6e] shadow-2xl"
          style={{
            fontFamily:
              'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
          }}
        >
          <div className="w-full pt-4">
            <div className="w-full h-[240px] px-2">
              <div className="relative flex h-full w-full flex-col overflow-hidden rounded-2xl bg-[#0b1a2a]/60 p-2 backdrop-blur-sm">
              {screenshotUrl ? (
                <>
                  {/* eslint-disable-next-line @next/next/no-img-element -- intentional for html-to-image capture */}
                  <img
                    alt=""
                    src={screenshotUrl}
                    crossOrigin="anonymous"
                    className="absolute inset-0 h-full w-full rounded-xl object-cover"
                  />
                  <div className="pointer-events-none absolute inset-0 rounded-xl bg-gradient-to-t from-[#0b1a2a]/85 via-transparent to-transparent" />
                </>
              ) : (
                <div className="flex flex-1 flex-col items-center justify-center gap-2 px-4 text-center">
                  <span className="text-sm font-medium text-gray-300">
                    No screenshot
                  </span>
                  <span className="text-xs text-gray-500">
                    Attach a chart capture to show here
                  </span>
                </div>
              )}
              </div>
            </div>
          </div>

          <div className="flex flex-col px-8 py-6">
            <div className="mt-3 flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs tracking-widest text-gray-400">TRADE</p>
              <h2 className="text-3xl font-bold leading-tight text-white">
                {trade.ticker ?? "—"}
              </h2>
            </div>
            {codeTrim ? (
              <div className="shrink-0 rounded-full border border-emerald-400/20 bg-emerald-500/20 px-3 py-1 text-xs text-emerald-400">
                CODE: {codeTrim}
              </div>
            ) : (
              <span
                className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium uppercase tracking-wide ${
                  longShort === "long"
                    ? "border border-emerald-400/20 bg-emerald-500/15 text-emerald-400"
                    : longShort === "short"
                      ? "border border-red-400/20 bg-red-500/15 text-red-400"
                      : "border border-white/10 bg-white/5 text-gray-400"
                }`}
              >
                {dir}
              </span>
            )}
            </div>

            <div className="mt-4">
            <p className="text-xs tracking-wide text-gray-400">P&amp;L</p>
            <h1
              className={`mt-1 text-4xl font-extrabold tabular-nums tracking-tight leading-tight md:text-5xl ${
                !hasPnl
                  ? "text-gray-400"
                  : positive
                    ? "text-emerald-400"
                    : "text-red-400/90"
              }`}
            >
              {formatMoney(trade.pnl)}
            </h1>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-6">
            <div className="rounded-xl border border-white/10 bg-white/5 p-6">
              <p className="text-xs tracking-wide text-gray-400">CONTRACTS</p>
              <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                {contracts}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-6">
              <p className="text-xs tracking-wide text-gray-400">POINTS</p>
              <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                {points}
              </p>
            </div>
            <div className="col-span-2 rounded-xl border border-white/10 bg-white/5 p-6">
              <p className="text-xs tracking-wide text-gray-400">RR</p>
              <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                {formatNumber(trade.rr)}
              </p>
            </div>
            <div className="col-span-2 rounded-xl border border-white/10 bg-white/5 p-6">
              <p className="text-xs tracking-wide text-gray-400">SESSION</p>
              <p className="mt-1 text-lg font-medium leading-snug text-white">
                {session}
              </p>
            </div>
            </div>

            {dateStr ? (
              <div className="mt-4 text-center text-sm text-gray-400">{dateStr}</div>
            ) : null}
          </div>
        </div>
      </div>
    )
  }
)

TradeShareCard.displayName = "TradeShareCard"

export default TradeShareCard
