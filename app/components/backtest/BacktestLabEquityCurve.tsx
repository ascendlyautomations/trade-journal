"use client"

import DashboardEquityCurve, {
  type DashboardEquityCurveProps,
} from "@/app/components/dashboard/DashboardEquityCurve"

type BacktestLabEquityCurveProps = Omit<
  DashboardEquityCurveProps,
  "variant" | "timeframeLabel" | "drawdownLimitLineY" | "equityCurveUsesAccountBalance" | "showPersonalDrawdownFloor"
> & {
  onLogTrade: () => void
}

export default function BacktestLabEquityCurve({
  data,
  totalTrades = 0,
  onLogTrade,
  ...chartProps
}: BacktestLabEquityCurveProps) {
  const showEmpty = data.length === 0 || totalTrades === 0

  if (showEmpty) {
    return (
      <div className="backtest-lab-section-card mb-5">
        <h2 className="backtest-lab-section-title mb-2">Backtest equity curve</h2>
        <div className="flex flex-col items-center px-2 py-6 text-center sm:py-8">
          <p className="max-w-md text-sm leading-relaxed text-[var(--tt-bl-control-muted)]">
            Log backtest trades to chart cumulative P&amp;L for your current
            filters. Backtest data stays separate from live dashboard history.
          </p>
          <button
            type="button"
            onClick={onLogTrade}
            className="mt-4 rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-400/60"
          >
            Log Backtest Trade
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="backtest-lab-equity-shell mb-5 space-y-3">
      <DashboardEquityCurve
        {...chartProps}
        data={data}
        totalTrades={totalTrades}
        variant="mobile"
      />
      <DashboardEquityCurve
        {...chartProps}
        data={data}
        totalTrades={totalTrades}
        variant="desktop"
      />
    </div>
  )
}
