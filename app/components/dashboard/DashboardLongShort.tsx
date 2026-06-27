"use client"

import EmptyState from "@/app/components/ui/EmptyState"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import type { DirectionEdge, LongShortPerformance } from "@/lib/dashboardLongShortStats"

function formatNumber(value: number) {
  if (value === null || value === undefined) return "-"
  return value.toLocaleString()
}

function formatExpectancy(value: number | null) {
  if (value === null) return "—"
  return formatCurrency(value)
}

function formatProfitFactor(value: number | null) {
  if (value === null) return "—"
  return formatDecimal(value)
}

function formatAvgRR(value: number | null) {
  if (value === null) return "—"
  return formatRR(value)
}

type SideCardProps = {
  label: string
  accentClass: string
  stats: NonNullable<LongShortPerformance["long"]>
}

function SideCard({ label, accentClass, stats }: SideCardProps) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 p-3 md:p-4 text-xs md:text-sm">
      <p className={`mb-3 font-semibold ${accentClass}`}>{label}</p>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-x-4">
        <div className="space-y-1.5 text-gray-300">
          <p>
            <span className="text-gray-400">Trades:</span>{" "}
            {formatNumber(stats.totalTrades)}
          </p>
          <p
            className={`font-semibold tabular-nums ${
              stats.totalPnL >= 0 ? "text-green-400" : "text-red-400"
            }`}
          >
            <span className="font-normal text-gray-400">Total P&amp;L:</span>{" "}
            {formatCurrency(stats.totalPnL)}
          </p>
          <p>
            <span className="text-gray-400">Avg P&amp;L:</span>{" "}
            <span
              className={
                stats.avgPnL >= 0 ? "text-green-400" : "text-red-400"
              }
            >
              {formatCurrency(stats.avgPnL)}
            </span>
          </p>
          {stats.bestTrade != null ? (
            <p>
              <span className="text-gray-400">Best trade:</span>{" "}
              <span className="text-green-400 tabular-nums">
                {formatCurrency(stats.bestTrade)}
              </span>
            </p>
          ) : null}
          {stats.worstTrade != null ? (
            <p>
              <span className="text-gray-400">Worst trade:</span>{" "}
              <span className="text-red-400 tabular-nums">
                {formatCurrency(stats.worstTrade)}
              </span>
            </p>
          ) : null}
        </div>

        <div className="space-y-1.5 text-gray-300">
          <p>
            <span className="text-gray-400">Win rate:</span>{" "}
            {stats.winRate.toFixed(1)}%
          </p>
          <p>
            <span className="text-gray-400">Avg RR:</span>{" "}
            {formatAvgRR(stats.avgRR)}
          </p>
          <p>
            <span className="text-gray-400">Profit factor:</span>{" "}
            <span
              className={
                stats.profitFactor >= 1 ? "text-green-400" : "text-red-400"
              }
            >
              {formatDecimal(stats.profitFactor)}
            </span>
          </p>
          <p>
            <span className="text-gray-400">Expectancy:</span>{" "}
            <span
              className={
                stats.expectancy >= 0 ? "text-green-400" : "text-red-400"
              }
            >
              {formatCurrency(stats.expectancy)}
            </span>
          </p>
          <p>
            <span className="text-gray-400">Best win streak:</span>{" "}
            {formatNumber(stats.bestWinStreak)}
          </p>
        </div>
      </div>
    </div>
  )
}

function DirectionEdgePanel({ edge }: { edge: DirectionEdge }) {
  const verdictClass =
    edge.verdict === "long"
      ? "text-emerald-300"
      : edge.verdict === "short"
        ? "text-sky-300"
        : edge.verdict === "balanced"
          ? "text-gray-200"
          : "text-gray-400"

  return (
    <div className="rounded-lg border border-white/10 bg-white/5 p-3 md:p-4">
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-300">
        Direction Edge
      </h3>
      <p className={`text-sm font-medium leading-snug ${verdictClass}`}>
        {edge.message}
      </p>
      <div className="mt-3 space-y-1 text-[11px] md:text-xs text-gray-400">
        <p>
          <span className="font-medium text-gray-200">Expectancy:</span>{" "}
          Long {formatExpectancy(edge.longExpectancy)} · Short{" "}
          {formatExpectancy(edge.shortExpectancy)}
        </p>
        <p>
          <span className="font-medium text-gray-200">Profit factor:</span>{" "}
          Long {formatProfitFactor(edge.longProfitFactor)} · Short{" "}
          {formatProfitFactor(edge.shortProfitFactor)}
        </p>
      </div>
    </div>
  )
}

export type DashboardLongShortProps = {
  performance: LongShortPerformance
  totalTrades?: number
}

export default function DashboardLongShort({
  performance,
  totalTrades = 0,
}: DashboardLongShortProps) {
  const showEmpty = totalTrades === 0

  return (
    <div className="flex min-h-[200px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        Long vs Short
      </h2>
      {showEmpty ? (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="py-8"
        />
      ) : !performance.hasDirectionData ? (
        <EmptyState
          title="No direction data"
          description="Add trade direction to compare long vs short performance."
          className="py-8"
        />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {performance.long ? (
            <SideCard
              label="Long"
              accentClass="text-emerald-400"
              stats={performance.long}
            />
          ) : (
            <div className="rounded-lg border border-white/10 bg-white/5 p-3 md:p-4 text-xs text-gray-400">
              No long trades in current filters.
            </div>
          )}
          {performance.short ? (
            <SideCard
              label="Short"
              accentClass="text-sky-400"
              stats={performance.short}
            />
          ) : (
            <div className="rounded-lg border border-white/10 bg-white/5 p-3 md:p-4 text-xs text-gray-400">
              No short trades in current filters.
            </div>
          )}
          <DirectionEdgePanel edge={performance.directionEdge} />
        </div>
      )}
    </div>
  )
}
