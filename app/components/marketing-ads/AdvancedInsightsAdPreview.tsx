"use client"

import DashboardSessionChart from "@/app/components/dashboard/DashboardSessionChart"
import DashboardWeekdayChart from "@/app/components/dashboard/DashboardWeekdayChart"
import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightHelperClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import {
  PerformanceInsightLine,
  PositiveInsightLine,
  SymbolInsightLine,
} from "@/app/components/dashboard/DashboardInsightHighlight"
import { formatCurrency } from "@/lib/formatCurrency"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import { generateTradingReport } from "@/lib/tradingReports/generateTradingReport"
import { getMarketingDashboardData } from "./marketingDemoData"
import InstagramAdShell from "./InstagramAdShell"

export default function AdvancedInsightsAdPreview() {
  const {
    stats,
    sessionBuckets,
    sessionPieData,
    weekdayChart,
    bestSession,
    bestSymbol,
  } = getMarketingDashboardData()

  const report = generateTradingReport(DEMO_TRADES, "monthly_this")

  const bestSessionText = bestSession
    ? `You perform best trading ${bestSession.name} session (${formatCurrency(bestSession.avg)} avg, ${bestSession.winRate.toFixed(0)}% win rate)`
    : null

  return (
    <InstagramAdShell
      title="Find Your Trading Edge"
      subtitle="Discover your strongest sessions, symbols, directions, setups, and behavioral patterns."
      settleMs={1200}
    >
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div className="min-h-0 [&_.min-h-\[260px\]]:min-h-[240px] [&_.md\:min-h-\[300px\]]:md:min-h-[240px]">
            <DashboardSessionChart
              sessionPieData={sessionPieData}
              sessionBuckets={sessionBuckets}
              totalTrades={stats.totalTrades}
            />
          </div>
          <div className="min-h-0 [&_.min-h-\[260px\]]:min-h-[240px] [&_.md\:min-h-\[300px\]]:md:min-h-[240px] [&_.h-\[280px\]]:h-[200px]">
            <DashboardWeekdayChart
              data={weekdayChart}
              totalTrades={stats.totalTrades}
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className={dashboardInsightCardClass}>
            <h3 className={dashboardInsightTitleClass}>Performance Insights</h3>
            <p className={dashboardInsightHelperClass}>
              Data-driven highlights from your trading history.
            </p>
            <div className="space-y-2">
              {bestSessionText ? (
                <p className={dashboardInsightBodyClass}>
                  • <PerformanceInsightLine text={bestSessionText} />
                </p>
              ) : null}
              {bestSymbol ? (
                <p className={dashboardInsightBodyClass}>
                  •{" "}
                  <SymbolInsightLine
                    symbol={bestSymbol.name}
                    avgPnL={bestSymbol.avg}
                  />
                </p>
              ) : null}
              {report.metrics.bestSessionLabel ? (
                <p className={dashboardInsightBodyClass}>
                  • Best session this period:{" "}
                  <span className="font-semibold text-emerald-300">
                    {report.metrics.bestSessionLabel}
                  </span>
                </p>
              ) : null}
              {report.metrics.mostTradedSymbol ? (
                <p className={dashboardInsightBodyClass}>
                  • Most traded symbol:{" "}
                  <span className="font-semibold text-gray-100">
                    {report.metrics.mostTradedSymbol}
                  </span>
                </p>
              ) : null}
            </div>
          </div>

          <div className={dashboardInsightCardClass}>
            <h3 className={dashboardInsightTitleClass}>
              {report.title || "Trading Report"}
            </h3>
            <p className={dashboardInsightHelperClass}>
              {report.dateRangeLabel}
            </p>
            <div className="space-y-2">
              {report.strengths.slice(0, 3).map((item) => (
                <p key={item} className={dashboardInsightBodyClass}>
                  • <PositiveInsightLine text={item} />
                </p>
              ))}
              {report.strengths.length === 0 ? (
                <p className={dashboardInsightBodyClass}>
                  {report.executiveSummary}
                </p>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    </InstagramAdShell>
  )
}
