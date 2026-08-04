"use client"

import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import {
  DASHBOARD_MOBILE_CARD_PAD_CLASS,
  DASHBOARD_MOBILE_CARD_TITLE_CLASS,
} from "@/app/components/dashboard/dashboardMobileUi"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import type {
  DirectionEdge,
  LongShortPerformance,
  LongShortSideStats,
} from "@/lib/dashboardLongShortStats"

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
    <div className="rounded-lg border border-white/10 bg-white/5 p-2.5 text-[11px] md:p-4 md:text-sm">
      <p className={`mb-2 font-semibold md:mb-3 ${accentClass}`}>{label}</p>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 sm:gap-x-4 md:gap-3">
        <div className="space-y-1 text-gray-300 md:space-y-1.5">
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

        <div className="space-y-1 text-gray-300 md:space-y-1.5">
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
    <div className="rounded-lg border border-white/10 bg-white/5 p-2.5 md:p-4">
      <h3 className="mb-1.5 text-[10px] font-semibold uppercase tracking-wide text-gray-200 md:mb-2 md:text-xs md:text-gray-400">
        Direction Edge
      </h3>
      <p className={`text-xs font-medium leading-snug md:text-sm ${verdictClass}`}>
        {edge.message}
      </p>
      <div className="mt-3 space-y-1 text-[11px] text-gray-200 md:text-xs md:text-gray-400">
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

function pnlClass(value: number | null | undefined) {
  if (value == null) return "text-gray-400"
  return value >= 0 ? "text-green-400" : "text-red-400"
}

function pfClass(value: number | null | undefined) {
  if (value == null) return "text-gray-400"
  return value >= 1 ? "text-green-400" : "text-red-400"
}

type CompareRow = {
  label: string
  long: string
  short: string
  longClass?: string
  shortClass?: string
}

function buildCompareRows(
  long: LongShortSideStats | null,
  short: LongShortSideStats | null
): CompareRow[] {
  return [
    {
      label: "Trades",
      long: long ? formatNumber(long.totalTrades) : "—",
      short: short ? formatNumber(short.totalTrades) : "—",
    },
    {
      label: "Total P&L",
      long: long ? formatCurrency(long.totalPnL) : "—",
      short: short ? formatCurrency(short.totalPnL) : "—",
      longClass: long ? pnlClass(long.totalPnL) : undefined,
      shortClass: short ? pnlClass(short.totalPnL) : undefined,
    },
    {
      label: "Avg P&L",
      long: long ? formatCurrency(long.avgPnL) : "—",
      short: short ? formatCurrency(short.avgPnL) : "—",
      longClass: long ? pnlClass(long.avgPnL) : undefined,
      shortClass: short ? pnlClass(short.avgPnL) : undefined,
    },
    {
      label: "Best Trade",
      long: long?.bestTrade != null ? formatCurrency(long.bestTrade) : "—",
      short: short?.bestTrade != null ? formatCurrency(short.bestTrade) : "—",
      longClass: long?.bestTrade != null ? "text-green-400" : undefined,
      shortClass: short?.bestTrade != null ? "text-green-400" : undefined,
    },
    {
      label: "Worst Trade",
      long: long?.worstTrade != null ? formatCurrency(long.worstTrade) : "—",
      short: short?.worstTrade != null ? formatCurrency(short.worstTrade) : "—",
      longClass: long?.worstTrade != null ? "text-red-400" : undefined,
      shortClass: short?.worstTrade != null ? "text-red-400" : undefined,
    },
    {
      label: "Win Rate",
      long: long ? `${long.winRate.toFixed(1)}%` : "—",
      short: short ? `${short.winRate.toFixed(1)}%` : "—",
    },
    {
      label: "Avg RR",
      long: long ? formatAvgRR(long.avgRR) : "—",
      short: short ? formatAvgRR(short.avgRR) : "—",
    },
    {
      label: "Profit Factor",
      long: long ? formatDecimal(long.profitFactor) : "—",
      short: short ? formatDecimal(short.profitFactor) : "—",
      longClass: long ? pfClass(long.profitFactor) : undefined,
      shortClass: short ? pfClass(short.profitFactor) : undefined,
    },
    {
      label: "Expectancy",
      long: long ? formatCurrency(long.expectancy) : "—",
      short: short ? formatCurrency(short.expectancy) : "—",
      longClass: long ? pnlClass(long.expectancy) : undefined,
      shortClass: short ? pnlClass(short.expectancy) : undefined,
    },
    {
      label: "Best Win Streak",
      long: long ? formatNumber(long.bestWinStreak) : "—",
      short: short ? formatNumber(short.bestWinStreak) : "—",
    },
  ]
}

/**
 * Full-width 3-column comparison table:
 * label | Long | Short — never stacked side cards.
 */
function LongShortCompareTable({
  long,
  short,
  edge,
}: {
  long: LongShortSideStats | null
  short: LongShortSideStats | null
  edge: DirectionEdge
}) {
  const rows = buildCompareRows(long, short)

  return (
    <div className="w-full min-w-0 space-y-2">
      <table
        className="w-full border-collapse"
        style={{ tableLayout: "fixed", width: "100%" }}
      >
        <colgroup>
          <col style={{ width: "36%" }} />
          <col style={{ width: "32%" }} />
          <col style={{ width: "32%" }} />
        </colgroup>
        <thead>
          <tr className="border-b border-white/10">
            <th scope="col" className="py-1.5 pr-2 text-left font-normal" />
            <th
              scope="col"
              className="px-1 py-1.5 text-center text-[10px] font-semibold uppercase tracking-wide text-emerald-400"
            >
              Long
            </th>
            <th
              scope="col"
              className="px-1 py-1.5 text-center text-[10px] font-semibold uppercase tracking-wide text-sky-400"
            >
              Short
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr
              key={row.label}
              className="border-b border-white/5 last:border-b-0"
            >
              <th
                scope="row"
                className="py-1.5 pr-2 text-left text-[11px] font-normal text-gray-200"
              >
                {row.label}
              </th>
              <td
                className={`px-1 py-1.5 text-center text-[11px] font-semibold tabular-nums whitespace-nowrap ${
                  row.longClass ?? "text-gray-200"
                }`}
              >
                {row.long}
              </td>
              <td
                className={`px-1 py-1.5 text-center text-[11px] font-semibold tabular-nums whitespace-nowrap ${
                  row.shortClass ?? "text-gray-200"
                }`}
              >
                {row.short}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <DirectionEdgePanel edge={edge} />
    </div>
  )
}

function LongShortStackedCards({
  performance,
}: {
  performance: LongShortPerformance
}) {
  return (
    <div className="grid grid-cols-1 gap-2 md:gap-3">
      {performance.long ? (
        <SideCard
          label="Long"
          accentClass="text-emerald-400"
          stats={performance.long}
        />
      ) : (
        <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-xs text-gray-400 md:p-4">
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
        <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-xs text-gray-400 md:p-4">
          No short trades in current filters.
        </div>
      )}
      <DirectionEdgePanel edge={performance.directionEdge} />
    </div>
  )
}

export type DashboardLongShortProps = {
  performance: LongShortPerformance
  totalTrades?: number
  /**
   * Force the mobile comparison table (used by the mobile Analytics tab so
   * breakpoint CSS cannot fall back to stacked Long/Short cards).
   */
  layout?: "compare" | "stacked" | "auto"
}

export default function DashboardLongShort({
  performance,
  totalTrades = 0,
  layout = "auto",
}: DashboardLongShortProps) {
  const showEmpty = totalTrades === 0

  return (
    <div
      className={`flex h-full min-h-[180px] flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md max-md:h-auto max-md:min-h-0 md:min-h-[200px] md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}
    >
      <h2
        className={`mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base ${DASHBOARD_MOBILE_CARD_TITLE_CLASS}`}
      >
        Long vs Short
      </h2>
      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : !performance.hasDirectionData ? (
        <DashboardWidgetEmptyState
          variant="needs-direction"
          className="py-8"
        />
      ) : layout === "compare" ? (
        <LongShortCompareTable
          long={performance.long}
          short={performance.short}
          edge={performance.directionEdge}
        />
      ) : layout === "stacked" ? (
        <LongShortStackedCards performance={performance} />
      ) : (
        <>
          {/* Mobile: comparison table across full card width */}
          <div className="block w-full min-w-0 md:hidden">
            <LongShortCompareTable
              long={performance.long}
              short={performance.short}
              edge={performance.directionEdge}
            />
          </div>
          {/* Desktop: original stacked cards */}
          <div className="hidden md:block">
            <LongShortStackedCards performance={performance} />
          </div>
        </>
      )}
    </div>
  )
}
