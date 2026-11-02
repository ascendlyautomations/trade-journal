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

  const netPnlLabel = formatPnlCurrency(periodStats.totalPnl, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })

  return (
    <>
      <div className="mb-3 space-y-2 md:hidden">
        <div className="flex w-full overflow-hidden rounded-[14px] border border-[var(--tt-bl-card-border)] bg-[var(--tt-bl-card-bg)]">
          {[
            { id: "trades", label: "Trades", value: String(periodStats.totalTrades), className: "" },
            { id: "winRate", label: "Win Rate", value: winRate, className: "" },
            {
              id: "pnl",
              label: "Total PnL",
              value: netPnlLabel,
              className: pnlClass,
            },
            {
              id: "avgRR",
              label: "Avg RR",
              value: formatRR(periodStats.avgRR),
              className: "",
            },
          ].map((chip, index) => (
            <div
              key={chip.id}
              className={`flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 px-0.5 py-2 ${
                index > 0 ? "border-l border-[var(--tt-bl-card-border)]" : ""
              }`}
            >
              <p className="max-w-full text-center text-[9px] leading-[1.15] text-[var(--tt-bl-control-muted)]">
                {chip.label}
              </p>
              <p
                className={`max-w-full truncate text-center text-[12px] font-semibold leading-tight tabular-nums text-[var(--tt-bl-control-text)] ${chip.className}`}
              >
                {chip.value}
              </p>
            </div>
          ))}
        </div>
        <div className="rounded-[14px] border border-[var(--tt-bl-card-border)] bg-[var(--tt-bl-card-bg)] px-3 py-2 text-[13px]">
          <span className="font-medium text-emerald-400">
            Wins: {periodStats.winningTrades}
          </span>
          <span className="px-1.5 text-[var(--tt-bl-control-muted)]">·</span>
          <span className="font-medium text-red-400">
            Losses: {periodStats.losingTrades}
          </span>
        </div>
        <div className="grid grid-cols-2 gap-2">
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
          <StatTile
            label="Max drawdown"
            value={formatPnlCurrency(maxDrawdown, {
              minimumFractionDigits: 0,
              maximumFractionDigits: 2,
            })}
            valueClassName="text-red-400"
          />
          <StatTile
            label="Avg win / loss"
            value={`${formatPnlCurrency(periodStats.avgWin ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })} / ${formatPnlCurrency(periodStats.avgLoss ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`}
          />
          <StatTile
            label="Best / worst"
            value={`${formatPnlCurrency(periodStats.largestWin ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })} / ${formatPnlCurrency(periodStats.largestLoss ?? 0, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`}
          />
          <StatTile
            label="Win / loss streak"
            value={`${periodStats.longestWinStreak} / ${periodStats.longestLossStreak}`}
          />
        </div>
      </div>
      <div className="mb-4 hidden grid-cols-2 gap-3 md:grid md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
        <StatTile
          label="Net P&L"
          value={netPnlLabel}
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
    </>
  )
}
