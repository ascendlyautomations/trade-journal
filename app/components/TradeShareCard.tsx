"use client"

import { forwardRef } from "react"

export type TradeShareCardProps = {
  trade: any
  /** For html-to-image: target this id with `document.getElementById` */
  exportId?: string
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

/**
 * Fixed-layout card for PNG export (Instagram-friendly 4:5-ish proportions).
 */
const TradeShareCard = forwardRef<HTMLDivElement, TradeShareCardProps>(
  function TradeShareCard({ trade, exportId }, ref) {
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

    const dateStr =
      trade.created_at != null
        ? new Date(trade.created_at).toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
            year: "numeric",
          })
        : ""

    return (
      <div
        ref={ref}
        id={exportId}
        className="box-border w-[420px] overflow-hidden rounded-3xl border border-white/[0.12] shadow-2xl"
        style={{
          backgroundColor: "#0a0f1c",
          fontFamily:
            'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
        }}
      >
        <div className="relative aspect-[4/3] w-full bg-black/50">
          {screenshotUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- intentional for html-to-image capture
            <img
              alt=""
              src={screenshotUrl}
              crossOrigin="anonymous"
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full min-h-[200px] flex-col items-center justify-center gap-2 bg-gradient-to-br from-white/[0.06] to-transparent px-6 text-center">
              <span className="text-sm font-medium text-gray-400">
                No screenshot
              </span>
              <span className="text-xs text-gray-600">
                Chart capture will appear here when attached
              </span>
            </div>
          )}
        </div>

        <div className="space-y-5 px-7 pb-8 pt-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-500">
                Trade
              </p>
              <p className="mt-1 text-3xl font-bold tracking-tight text-white">
                {trade.ticker ?? "—"}
              </p>
            </div>
            <span
              className={`mt-7 shrink-0 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-wide ${
                longShort === "long"
                  ? "border-emerald-400/40 bg-emerald-500/15 text-emerald-300"
                  : longShort === "short"
                    ? "border-rose-400/40 bg-rose-500/15 text-rose-300"
                    : "border-white/20 bg-white/10 text-gray-300"
              }`}
            >
              {dir}
            </span>
          </div>

          <div>
            <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">
              P&amp;L
            </p>
            <p
              className={`mt-1 text-[2.65rem] font-bold leading-none tabular-nums tracking-tight ${
                !hasPnl
                  ? "text-slate-400"
                  : positive
                    ? "text-emerald-400"
                    : "text-red-400"
              }`}
            >
              {formatMoney(trade.pnl)}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm">
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
                Risk-reward (RR)
              </p>
              <p className="mt-1 font-semibold tabular-nums text-white">
                {formatNumber(trade.rr)}
              </p>
            </div>
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
                Contracts
              </p>
              <p className="mt-1 font-semibold tabular-nums text-white">
                {contracts}
              </p>
            </div>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3 text-sm">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
              Session
            </p>
            <p className="mt-1 font-medium text-gray-100">{session}</p>
          </div>

          {dateStr ? (
            <p className="text-center text-xs text-slate-600">{dateStr}</p>
          ) : null}
        </div>
      </div>
    )
  }
)

TradeShareCard.displayName = "TradeShareCard"

export default TradeShareCard
