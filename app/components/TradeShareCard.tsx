"use client"

import { forwardRef } from "react"
import { formatMoneyUnknown } from "@/lib/formatDisplay"
import { publicAccountBadgeFromTrade } from "@/lib/publicAccountPrivacy"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import { TRADE_SHARE_EXPORT_WIDTH } from "@/lib/tradeShareExport"

export type TradeShareCardProps = {
  trade: any
  /** For html-to-image: target this id with `document.getElementById` */
  exportId?: string
  profile?: { referral_code?: string | null; username?: string | null } | null
}

function formatNumber(value: unknown, digits = 2): string {
  if (value === null || value === undefined) return "—"
  const number = Number(value)
  if (Number.isNaN(number)) return "—"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
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

function publicAccountLabel(trade: any): string {
  return publicAccountBadgeFromTrade(trade) ?? "—"
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

function formatShareDateTime(value: unknown): string {
  const date = parseDateLike(value)
  if (!date) return "—"
  return date.toLocaleString("en-US", {
    timeZone: "America/New_York",
    month: "numeric",
    day: "numeric",
    year: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
}

/** Responsive export card — premium blue TradeTraxs layout. */
const TradeShareCard = forwardRef<HTMLDivElement, TradeShareCardProps>(
  function TradeShareCard({ trade, exportId, profile }, ref) {
    const screenshotUrl = tradeScreenshotPublicUrl(trade?.image_url)
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

    const rr = formatNumber(trade.rr)
    const account = publicAccountLabel(trade)
    const entryDisplay = formatShareDateTime(
      trade.entry_time ?? trade.date ?? trade.trade_date
    )
    const exitDisplay = formatShareDateTime(trade.exit_time)
    const timeRange =
      entryDisplay !== "—" && exitDisplay !== "—"
        ? `${entryDisplay} → ${exitDisplay}`
        : entryDisplay !== "—"
          ? entryDisplay
          : exitDisplay !== "—"
            ? exitDisplay
            : "—"

    const codeTrim =
      profile?.referral_code != null &&
      String(profile.referral_code).trim() !== ""
        ? String(profile.referral_code).trim()
        : null

    const usernameTrim =
      profile?.username != null && String(profile.username).trim() !== ""
        ? String(profile.username).trim().replace(/^@+/, "")
        : null

    return (
      <div
        className="mx-auto box-border shrink-0"
        style={{ width: TRADE_SHARE_EXPORT_WIDTH }}
      >
        <div
          ref={ref}
          id={exportId}
          className="relative overflow-hidden rounded-[28px] border border-cyan-300/20 bg-gradient-to-br from-[#061427] via-[#0b2d55] to-[#0f7ea8] shadow-2xl"
          style={{
            width: TRADE_SHARE_EXPORT_WIDTH,
            minWidth: TRADE_SHARE_EXPORT_WIDTH,
            boxSizing: "border-box",
            fontFamily:
              'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
          }}
        >
          <div className="pointer-events-none absolute -right-20 -top-20 h-44 w-44 rounded-full bg-cyan-400/25 blur-3xl" />
          <div className="pointer-events-none absolute -bottom-16 -left-20 h-48 w-48 rounded-full bg-blue-500/20 blur-3xl" />

          <div className="relative p-4 pb-0">
            <div className="relative h-[176px] w-full overflow-hidden rounded-2xl border border-cyan-300/20 bg-[#07152a]/70 shadow-inner shadow-black/30">
              {screenshotUrl ? (
                <>
                  {/* eslint-disable-next-line @next/next/no-img-element -- intentional for html-to-image capture */}
                  <img
                    alt="Trade screenshot"
                    src={screenshotUrl}
                    crossOrigin="anonymous"
                    className="h-full w-full object-cover"
                  />
                  <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-[#061427]/80 via-transparent to-transparent" />
                </>
              ) : (
                <div className="flex h-full flex-col items-center justify-center gap-2 px-4 text-center">
                  <span className="text-sm font-semibold text-cyan-100">
                    No screenshot
                  </span>
                  <span className="max-w-[240px] text-xs text-blue-100/60">
                    Attach a chart capture to show here
                  </span>
                </div>
              )}
            </div>
          </div>

          <div className="relative flex flex-col px-6 pb-5 pt-5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[10px] font-semibold uppercase tracking-[0.28em] text-cyan-200/70">
                  Trade Recap
                </p>
                <h2 className="mt-1 truncate text-4xl font-black leading-none tracking-tight text-white">
                  {trade.ticker ?? "—"}
                </h2>
              </div>
              <span
                className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-bold uppercase tracking-wide ${
                  longShort === "long"
                    ? "border border-emerald-300/30 bg-emerald-400/15 text-emerald-200"
                    : longShort === "short"
                      ? "border border-red-300/30 bg-red-400/15 text-red-200"
                      : "border border-cyan-300/20 bg-cyan-300/10 text-cyan-100"
                }`}
              >
                {dir}
              </span>
            </div>

            <div className="mt-4 rounded-2xl border border-cyan-300/15 bg-[#031022]/45 px-4 py-4">
              <p className="text-[10px] font-semibold uppercase tracking-[0.24em] text-blue-100/60">
                Profit / Loss
              </p>
              <h1
                className={`mt-1 text-[2.5rem] font-black leading-none tabular-nums tracking-tight ${
                  !hasPnl
                    ? "text-gray-300"
                    : positive
                      ? "text-emerald-300"
                      : "text-red-300"
                }`}
              >
                {formatMoneyUnknown(trade.pnl, { empty: "—" })}
              </h1>
            </div>

            <div className="mt-4 grid grid-cols-3 gap-2">
              {[
                ["RR", rr],
                ["Points", points],
                ["Contracts", contracts],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="rounded-xl border border-cyan-300/10 bg-white/[0.06] px-3 py-3 text-center"
                >
                  <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-100/55">
                    {label}
                  </p>
                  <p className="mt-1 text-base font-bold tabular-nums text-white">
                    {value}
                  </p>
                </div>
              ))}
            </div>

            <div className="mt-3 grid grid-cols-2 gap-2">
              <div className="rounded-xl border border-cyan-300/10 bg-white/[0.05] px-3 py-3">
                <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-100/55">
                  Session
                </p>
                <p className="mt-1 truncate text-sm font-semibold text-white">
                  {session}
                </p>
              </div>
              <div className="rounded-xl border border-cyan-300/10 bg-white/[0.05] px-3 py-3">
                <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-100/55">
                  Account
                </p>
                <p className="mt-1 truncate text-sm font-semibold text-white">
                  {account}
                </p>
              </div>
            </div>

            <div className="mt-3 rounded-xl border border-cyan-300/10 bg-[#031022]/40 px-3 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-100/55">
                Entry / Exit
              </p>
              <p className="mt-1 text-sm font-medium leading-snug text-cyan-50">
                {timeRange}
              </p>
            </div>

            <div className="mt-5 flex items-center justify-between border-t border-cyan-300/15 pt-4">
              <div className="flex min-w-0 flex-1 items-center gap-2">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-cyan-300/30 bg-cyan-300/15 text-xs font-black text-cyan-100">
                  TT
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-black leading-none tracking-tight text-white">
                    TradeTraxs
                  </p>
                  <p className="mt-0.5 flex min-w-0 items-center justify-between gap-3 text-[9px] uppercase tracking-[0.22em] text-cyan-100/55">
                    <span className="shrink-0">Journal. Review. Improve.</span>
                    {usernameTrim ? (
                      <span className="truncate font-medium normal-case tracking-normal text-cyan-100/40">
                        - @{usernameTrim}
                      </span>
                    ) : null}
                  </p>
                </div>
              </div>

              {codeTrim ? (
                <div className="rounded-full border border-cyan-300/20 bg-cyan-300/10 px-2.5 py-1 text-[10px] font-semibold text-cyan-100">
                  CODE {codeTrim}
                </div>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    )
  }
)

TradeShareCard.displayName = "TradeShareCard"

export default TradeShareCard
