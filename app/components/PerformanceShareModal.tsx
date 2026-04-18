"use client"

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react"
import { toPng } from "html-to-image"
import PerformanceShareCard from "./PerformanceShareCard"
import {
  type PerformanceWindow,
  buildEquityCurveFromTrades,
  computePerformanceStats,
  filterTradesByPerformanceWindow,
  formatPerformanceShareDateRange,
  performanceWindowLabel,
} from "@/lib/performanceShare"

const WINDOWS: PerformanceWindow[] = ["daily", "weekly", "monthly", "yearly"]

export type PerformanceShareModalProps = {
  open: boolean
  onClose: () => void
  /** Trades already scoped by account / mode / date filters (not timeframe). */
  tradePool: any[]
  /** Shown under the period title */
  subtitle?: string
}

export default function PerformanceShareModal({
  open,
  onClose,
  tradePool,
  subtitle,
}: PerformanceShareModalProps) {
  const [windowKey, setWindowKey] = useState<PerformanceWindow>("monthly")
  const [busy, setBusy] = useState(false)
  const lockRef = useRef(false)
  const exportId = useId().replace(/:/g, "perf-share")

  const filtered = useMemo(
    () => filterTradesByPerformanceWindow(tradePool, windowKey),
    [tradePool, windowKey]
  )

  const stats = useMemo(() => computePerformanceStats(filtered), [filtered])

  const equityCurve = useMemo(
    () => buildEquityCurveFromTrades(filtered),
    [filtered]
  )

  const periodLabel = performanceWindowLabel(windowKey)
  const timeframeUpper = periodLabel.toUpperCase()
  const dateRangeLabel = useMemo(
    () => formatPerformanceShareDateRange(windowKey, filtered),
    [windowKey, filtered]
  )

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  const handleDownload = useCallback(async () => {
    const root = document.getElementById(exportId)
    if (!root || lockRef.current) return
    lockRef.current = true
    setBusy(true)
    try {
      await new Promise<void>((resolve) => {
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      })
      await new Promise<void>((resolve) => {
        window.setTimeout(resolve, 240)
      })
      const dataUrl = await toPng(root, {
        pixelRatio: 2,
        cacheBust: true,
        backgroundColor: "#0a0f1c",
      })
      const link = document.createElement("a")
      link.download = `performance-${windowKey}-${Date.now()}.png`
      link.href = dataUrl
      link.click()
    } catch (e) {
      console.error("Performance share export:", e)
    } finally {
      lockRef.current = false
      setBusy(false)
    }
  }, [exportId, windowKey])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-[200] flex items-end justify-center p-4 sm:items-center"
      role="presentation"
    >
      <button
        type="button"
        aria-label="Close"
        className="absolute inset-0 bg-black/70 backdrop-blur-sm transition-opacity motion-reduce:transition-none"
        onClick={onClose}
      />

      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="performance-share-title"
        className="relative z-10 max-h-[min(92vh,880px)] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/15 bg-[#0f172a]/98 p-5 shadow-2xl backdrop-blur-xl md:p-6"
      >
        <div className="mb-5 flex items-start justify-between gap-3">
          <div>
            <h2
              id="performance-share-title"
              className="text-lg font-semibold text-white md:text-xl"
            >
              Share performance
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              Pick a window, then download a PNG for Instagram or X.
            </p>
            {subtitle ? (
              <p className="mt-2 text-xs text-gray-500">{subtitle}</p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-sm text-gray-300 transition hover:bg-white/10"
          >
            Close
          </button>
        </div>

        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-500">
          Timeframe
        </p>
        <div className="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-4">
          {WINDOWS.map((w) => (
            <button
              key={w}
              type="button"
              onClick={() => setWindowKey(w)}
              className={`rounded-xl border px-3 py-2.5 text-sm font-semibold transition ${
                windowKey === w
                  ? "border-emerald-400/50 bg-emerald-500/20 text-emerald-100"
                  : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
              }`}
            >
              {performanceWindowLabel(w)}
            </button>
          ))}
        </div>

        <div className="mb-4 rounded-xl border border-white/10 bg-black/20 p-4">
          <div className="grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
            <div>
              <p className="text-xs text-gray-500">P&amp;L</p>
              <p
                className={`font-semibold tabular-nums ${
                  stats.totalPnL >= 0 ? "text-emerald-400" : "text-red-400"
                }`}
              >
                {Number.isFinite(stats.totalPnL)
                  ? formatMoney(stats.totalPnL)
                  : "—"}
              </p>
            </div>
            <div>
              <p className="text-xs text-gray-500">Win rate</p>
              <p className="font-semibold tabular-nums text-white">
                {stats.totalTrades ? `${stats.winRate.toFixed(1)}%` : "—"}
              </p>
            </div>
            <div>
              <p className="text-xs text-gray-500">Trades</p>
              <p className="font-semibold tabular-nums text-white">
                {stats.totalTrades}
              </p>
            </div>
            <div>
              <p className="text-xs text-gray-500">Avg RR</p>
              <p className="font-semibold tabular-nums text-white">
                {formatRR(stats.avgRR)}
              </p>
            </div>
          </div>
        </div>

        <div className="pointer-events-none fixed left-[-13000px] top-0 z-0" aria-hidden>
          <PerformanceShareCard
            exportId={exportId}
            equityCurve={equityCurve}
            timeframeTitle={timeframeUpper}
            timeframeBadge={timeframeUpper}
            stats={stats}
            dateRangeLabel={dateRangeLabel}
          />
        </div>

        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-semibold text-gray-200 transition hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => void handleDownload()}
            className="rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 px-4 py-2.5 text-sm font-semibold text-white shadow-lg shadow-emerald-500/10 transition hover:from-blue-600 hover:to-emerald-600 disabled:opacity-50"
          >
            {busy ? "Saving…" : "Download PNG"}
          </button>
        </div>
      </div>
    </div>
  )
}

function formatMoney(value: number): string {
  return value < 0
    ? `-$${Math.abs(value).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function formatRR(value: number): string {
  if (!Number.isFinite(value)) return "—"
  return value.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}
