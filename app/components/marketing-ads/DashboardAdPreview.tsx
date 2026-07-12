"use client"

import DashboardEquityCurve from "@/app/components/dashboard/DashboardEquityCurve"
import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import {
  PerformanceInsightLine,
  SymbolInsightLine,
  WeekdayInsightLine,
} from "@/app/components/dashboard/DashboardInsightHighlight"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { getMarketingDashboardData } from "./marketingDemoData"
import InstagramAdShell from "./InstagramAdShell"

function StatCard({
  title,
  value,
  positive,
}: {
  title: string
  value: string
  positive?: boolean
}) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="flex min-h-[88px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-md">
      <p className="mb-1 text-sm text-gray-300">{title}</p>
      <span
        className={`block text-xl font-semibold leading-tight tabular-nums ${color}`}
      >
        {value}
      </span>
    </div>
  )
}

export default function DashboardAdPreview() {
  const { stats, bestSession, bestSymbol, bestWeekday } =
    getMarketingDashboardData()

  const bestSessionText = bestSession
    ? `You perform best trading ${bestSession.name} session (${formatCurrency(bestSession.avg)} avg, ${bestSession.winRate.toFixed(0)}% win rate)`
    : null

  return (
    <InstagramAdShell
      title="See Your Trading Clearly"
      subtitle="Track performance, uncover patterns, and understand what is actually driving your results."
      settleMs={1200}
    >
      <div className="space-y-4">
        <div className="grid grid-cols-3 gap-3">
          <StatCard
            title="Net P/L"
            value={formatCurrency(stats.totalPnL)}
            positive={stats.totalPnL >= 0}
          />
          <StatCard title="Win Rate" value={`${stats.winRate.toFixed(1)}%`} />
          <StatCard title="Avg RR" value={formatRR(stats.avgRR)} />
          <StatCard title="Total Trades" value={String(stats.totalTrades)} />
          <StatCard
            title="Profit Factor"
            value={formatDecimal(stats.profitFactor)}
            positive={
              stats.profitFactor >= 1
                ? true
                : stats.profitFactor > 0
                  ? false
                  : undefined
            }
          />
          <StatCard
            title="Best Win Streak"
            value={String(stats.maxWinStreak)}
          />
        </div>

        <div className="overflow-hidden rounded-xl [&_.hidden]:!block">
          <DashboardEquityCurve
            data={stats.equityCurve}
            variant="desktop"
            isPro
            profitFactor={stats.profitFactor}
            currentStreak={stats.currentStreak}
            avgDay={stats.avgDay}
            consistency={stats.consistency}
            totalTrades={stats.totalTrades}
          />
        </div>

        <div className={dashboardInsightCardClass}>
          <h3 className={dashboardInsightTitleClass}>Performance Insights</h3>
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
            {bestWeekday ? (
              <p className={dashboardInsightBodyClass}>
                •{" "}
                <WeekdayInsightLine
                  weekday={bestWeekday.day}
                  avgPnL={bestWeekday.avg}
                />
              </p>
            ) : null}
          </div>
        </div>
      </div>
    </InstagramAdShell>
  )
}
