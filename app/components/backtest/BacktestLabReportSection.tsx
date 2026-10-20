"use client"

import { useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import TradingReportModal from "@/app/components/trading-reports/TradingReportModal"
import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { generateTradingReportForTrades } from "@/lib/tradingReports/generateTradingReport"
import type { TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"
import { tradesSelectedTradeHref } from "@/lib/tradesSelectedTrade"

export type BacktestLabReportSectionProps = {
  trades: any[]
  dateRangeLabel: string
  viewerUserId?: string | null
  minTrades?: number
}

const FIXED_PERIOD: TradingReportPeriodKey = "monthly_this"

export default function BacktestLabReportSection({
  trades,
  dateRangeLabel,
  viewerUserId,
  minTrades = 3,
}: BacktestLabReportSectionProps) {
  const router = useRouter()
  const [open, setOpen] = useState(false)

  const report = useMemo(
    () =>
      generateTradingReportForTrades(trades, {
        title: "Backtest Lab Report",
        dateRangeLabel,
        kind: "monthly",
      }),
    [trades, dateRangeLabel]
  )

  const bestTrade = useMemo(() => {
    if (!report.bestTradeId) return null
    return trades.find((t) => String(t.id) === report.bestTradeId) ?? null
  }, [report.bestTradeId, trades])

  const canGenerate = trades.length >= minTrades

  return (
    <section className="mb-6">
      <div className={`${dashboardInsightCardClass} space-y-3`}>
        <div>
          <h2 className="text-lg font-semibold text-white">Performance report</h2>
          <p className="text-sm text-gray-400">
            Strategy, session, and weekday insights for your filtered backtest trades
            only.
          </p>
        </div>
        {canGenerate ? (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500"
          >
            View backtest report
          </button>
        ) : (
          <p className="text-sm text-gray-400">
            Log at least {minTrades} backtest trades in this filter set to generate a
            report.
          </p>
        )}
      </div>

      <TradingReportModal
        open={open}
        onClose={() => setOpen(false)}
        report={report}
        periodKey={FIXED_PERIOD}
        onPeriodChange={() => {}}
        hidePeriodSelector
        bestTradeHeading="Best trade in selection"
        bestTrade={bestTrade}
        viewerUserId={viewerUserId}
        onViewTrade={(trade) => {
          if (trade.id) router.push(tradesSelectedTradeHref(String(trade.id)))
        }}
      />
    </section>
  )
}
