"use client"

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react"
import PerformanceShareCard from "./PerformanceShareCard"
import ShareToConversationsModal from "./ShareToConversationsModal"
import {
  PERFORMANCE_SHARE_EXPORT_WIDTH,
  captureShareCardElementToPng,
} from "@/lib/shareImageCapture"
import {
  type PerformanceWindow,
  type PerformanceWindowOptions,
  buildEquityCurveFromTrades,
  computePerformanceStats,
  filterTradesByPerformanceWindow,
  formatPerformanceShareDateRange,
  getPerformanceShareRangeBounds,
  performanceWindowLabel,
} from "@/lib/performanceShare"

const WINDOWS: PerformanceWindow[] = [
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "custom",
]

export type PerformanceShareModalProps = {
  open: boolean
  onClose: () => void
  /** Trades already scoped by account / mode / date filters (not timeframe). */
  tradePool: any[]
  /** Shown under the period title */
  subtitle?: string
  /** From parent fetch — referral code for export card */
  profile?: { referral_code?: string | null } | null
  /** Prefill custom range when opening from a page with custom filters. */
  initialCustomRangeStart?: string
  initialCustomRangeEnd?: string
}

export default function PerformanceShareModal({
  open,
  onClose,
  tradePool,
  subtitle,
  profile = null,
  initialCustomRangeStart = "",
  initialCustomRangeEnd = "",
}: PerformanceShareModalProps) {
  const [windowKey, setWindowKey] = useState<PerformanceWindow>("monthly")
  const [customRangeStart, setCustomRangeStart] = useState(
    initialCustomRangeStart
  )
  const [customRangeEnd, setCustomRangeEnd] = useState(initialCustomRangeEnd)
  const [busy, setBusy] = useState(false)
  const [perfShareActionsOpen, setPerfShareActionsOpen] = useState(false)
  const [perfDmOpen, setPerfDmOpen] = useState(false)
  const lockRef = useRef(false)
  const exportId = useId().replace(/:/g, "")

  const windowOptions = useMemo((): PerformanceWindowOptions => {
    if (windowKey !== "custom") return {}
    return {
      customRangeStart,
      customRangeEnd,
    }
  }, [windowKey, customRangeStart, customRangeEnd])

  const filtered = useMemo(
    () => filterTradesByPerformanceWindow(tradePool, windowKey, windowOptions),
    [tradePool, windowKey, windowOptions]
  )

  const stats = useMemo(() => computePerformanceStats(filtered), [filtered])

  const equityCurve = useMemo(
    () => buildEquityCurveFromTrades(filtered),
    [filtered]
  )

  const periodLabel = performanceWindowLabel(windowKey)
  const timeframeUpper =
    windowKey === "custom" && customRangeStart && customRangeEnd
      ? "CUSTOM"
      : periodLabel.toUpperCase()
  const dateRangeLabel = useMemo(
    () => formatPerformanceShareDateRange(windowKey, filtered, windowOptions),
    [windowKey, filtered, windowOptions]
  )

  const rangeBounds = useMemo(
    () => getPerformanceShareRangeBounds(windowKey, filtered, windowOptions),
    [windowKey, filtered, windowOptions]
  )

  useEffect(() => {
    if (!open) return
    console.log("[performanceShare]", {
      timeframe: windowKey,
      tradePoolCount: tradePool.length,
      filteredTradesCount: filtered.length,
      equityCurvePoints: equityCurve.length,
      stats,
      exportId,
      cardElementFound: Boolean(document.getElementById(exportId)),
    })
  }, [
    open,
    windowKey,
    tradePool.length,
    filtered.length,
    equityCurve.length,
    stats,
    exportId,
  ])

  useEffect(() => {
    if (!open) return
    setCustomRangeStart(initialCustomRangeStart)
    setCustomRangeEnd(initialCustomRangeEnd)
  }, [open, initialCustomRangeStart, initialCustomRangeEnd])

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

  useEffect(() => {
    if (!open) {
      setPerfShareActionsOpen(false)
      setPerfDmOpen(false)
    }
  }, [open])

  const handleDownload = useCallback(async () => {
    if (lockRef.current) return
    lockRef.current = true
    setBusy(true)
    try {
      console.log("[performanceShare] download start", {
        timeframe: windowKey,
        filteredTradesCount: filtered.length,
        equityCurvePoints: equityCurve.length,
        exportId,
      })
      const dataUrl = await captureShareCardElementToPng(exportId, {
        warmupMs: 520,
        logContext: "performanceShare",
      })
      const link = document.createElement("a")
      link.download = `performance-${windowKey}-${Date.now()}.png`
      link.href = dataUrl
      link.click()
      console.log("[performanceShare] download success")
    } catch (e) {
      console.error("[performanceShare] download failure:", e)
    } finally {
      lockRef.current = false
      setBusy(false)
    }
  }, [exportId, windowKey, filtered.length, equityCurve.length])

  const capturePerformancePng = useCallback(async () => {
    try {
      console.log("[performanceShare] DM capture start", {
        timeframe: windowKey,
        exportId,
      })
      const dataUrl = await captureShareCardElementToPng(exportId, {
        warmupMs: 520,
        logContext: "performanceShare",
      })
      console.log("[performanceShare] DM capture success")
      return dataUrl
    } catch (e) {
      console.error("[performanceShare] DM capture failure:", e)
      return null
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
        <div className="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-3">
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

        {windowKey === "custom" ? (
          <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label className="block text-sm text-gray-300">
              <span className="mb-1 block text-xs text-gray-500">Start date</span>
              <input
                type="date"
                value={customRangeStart}
                onChange={(e) => setCustomRangeStart(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-white"
              />
            </label>
            <label className="block text-sm text-gray-300">
              <span className="mb-1 block text-xs text-gray-500">End date</span>
              <input
                type="date"
                value={customRangeEnd}
                onChange={(e) => setCustomRangeEnd(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-white"
              />
            </label>
          </div>
        ) : null}

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

        <div
          className="pointer-events-none fixed top-0 overflow-hidden"
          style={{
            left: 0,
            width: PERFORMANCE_SHARE_EXPORT_WIDTH,
            opacity: 0,
            zIndex: -1,
          }}
          aria-hidden
        >
          <PerformanceShareCard
            exportId={exportId}
            equityCurve={equityCurve}
            timeframeTitle={timeframeUpper}
            profile={profile}
            stats={stats}
            rangeStart={rangeBounds?.start ?? null}
            rangeEnd={rangeBounds?.end ?? null}
            dateRangeFallback={dateRangeLabel}
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
          <button
            type="button"
            onClick={() => setPerfShareActionsOpen(true)}
            className="rounded-xl border border-emerald-400/40 bg-emerald-500/15 px-4 py-2.5 text-sm font-semibold text-emerald-100 transition hover:bg-emerald-500/25"
          >
            Share…
          </button>
        </div>
      </div>

      {perfShareActionsOpen ? (
        <div className="fixed inset-0 z-[210] flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-[#0b1f3a] p-5 shadow-xl">
            <h3 className="mb-4 text-lg font-semibold text-white">
              Share performance
            </h3>
            <div className="flex flex-col gap-3">
              <button
                type="button"
                onClick={() => {
                  void handleDownload()
                  setPerfShareActionsOpen(false)
                }}
                disabled={busy}
                className="w-full rounded-lg bg-green-500 py-2 font-medium text-black disabled:opacity-50"
              >
                Download Image
              </button>
              <button
                type="button"
                onClick={() => {
                  setPerfShareActionsOpen(false)
                  setPerfDmOpen(true)
                }}
                className="w-full rounded-lg bg-white/10 py-2 text-white hover:bg-white/20"
              >
                Send in Messages
              </button>
            </div>
            <button
              type="button"
              onClick={() => setPerfShareActionsOpen(false)}
              className="mt-4 text-sm text-white/50 hover:text-white"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}

      <ShareToConversationsModal
        open={perfDmOpen}
        onClose={() => setPerfDmOpen(false)}
        title="Send performance card"
        captionPlaceholder="Optional message with image…"
        imageDataUrlPromise={capturePerformancePng}
      />
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
