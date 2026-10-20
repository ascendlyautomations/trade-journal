"use client"

import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatProfitFactor, formatRR } from "@/lib/formatDisplay"
import type { PeriodTradeStats } from "@/lib/periodTradeStats"

type BacktestLabStatsGridProps = {
  periodStats: PeriodTradeStats
  expectancy: number | null
  maxDrawdown: number
}

function StatTile({
  label,
  value,
  valueClassName = "text-[var(--tt-bl-control-text)]",
}: {
  label: string
  value: string
  valueClassName?: string
}) {
  return (
    <div className="backtest-lab-stat-tile">
      <p className="backtest-lab-stat-label">{label}</p>
      <p className={`backtest-lab-stat-value ${valueClassName}`}>{value}</p>
    </div>
  )
}

export default function BacktestLabStatsGrid({
  periodStats,
  expectancy,
  maxDrawdown,
}: BacktestLabStatsGridProps) {
  const winRate =
    periodStats.winRate != null
      ? `${periodStats.winRate.toFixed(1)}%`
      : "0%"

  const profitFactorLabel = periodStats.profitFactorInfinite
    ? "∞"
    : formatProfitFactor(periodStats.profitFactor)

  const pnlClass =
    periodStats.totalPnl >= 0 ? "text-emerald-400" : "text-red-400"

  const expectancyClass =
    expectancy == null
      ? "text-[var(--tt-bl-control-muted)]"
      : expectancy >= 0
        ? "text-emerald-400"
        : "text-red-400"

  return (
    <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
      <StatTile
        label="Net P&L"
        value={formatPnlCurrency(periodStats.totalPnl, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })}
        valueClassName={pnlClass}
      />
      <StatTile label="Win rate" value={winRate} />
      <StatTile label="Profit factor" value={profitFactorLabel} />
      <StatTile
        label="Expectancy"
        value={
          expectancy != null
            ? formatPnlCurrency(expectancy, {
                minimumFractionDigits: 0,
                maximumFractionDigits: 2,
              })
            : "—"
        }
        valueClassName={expectancyClass}
      />
      <StatTile label="Average R" value={formatRR(periodStats.avgRR)} />
      <StatTile
        label="Max drawdown"
        value={formatPnlCurrency(maxDrawdown, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })}
        valueClassName="text-red-400"
      />
      <StatTile
        label="Trades"
        value={String(periodStats.totalTrades)}
      />
      <StatTile
        label="Avg win / loss"
        value={`${formatPnlCurrency(periodStats.avgWin ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })} / ${formatPnlCurrency(periodStats.avgLoss ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`}
      />
      <StatTile
        label="Best / worst trade"
        value={`${formatPnlCurrency(periodStats.largestWin ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })} / ${formatPnlCurrency(periodStats.largestLoss ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`}
      />
      <StatTile
        label="Win / loss streak"
        value={`${periodStats.longestWinStreak} / ${periodStats.longestLossStreak}`}
      />
    </div>
  )
}
