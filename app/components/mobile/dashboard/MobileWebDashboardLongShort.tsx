"use client"

import type {
  DirectionEdge,
  LongShortPerformance,
  LongShortSideStats,
} from "@/lib/dashboardLongShortStats"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR, formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { mobileWebBarShare } from "@/lib/mobileWebDashboardAnalytics"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { mwDashMoneyClass, mwDashText } from "./mobileWebDashboardChrome"

type MobileWebDashboardLongShortProps = {
  performance: LongShortPerformance
  totalTrades?: number
}

function formatCount(value: number) {
  return value.toLocaleString()
}

function SideColumn({
  title,
  swatch,
  stats,
  maxAbs,
}: {
  title: string
  swatch: string
  stats: LongShortSideStats | null
  maxAbs: number
}) {
  const share = stats ? mobileWebBarShare(stats.totalPnL, maxAbs) : 0
  const barColor =
    !stats || stats.totalPnL === 0
      ? "color-mix(in srgb, var(--tt-text) 18%, transparent)"
      : stats.totalPnL > 0
        ? "var(--tt-positive, #3ddc97)"
        : "var(--tt-negative, #ff7b72)"

  return (
    <div className="min-w-0 flex-1">
      <div className="mb-1.5 flex items-center gap-1.5">
        <span
          className="h-2 w-2 rounded-full"
          style={{ backgroundColor: swatch }}
          aria-hidden
        />
        <p className={`text-[13px] font-semibold ${mwDashText.primary}`}>{title}</p>
      </div>
      {stats ? (
        <>
          <p
            className={`text-[20px] font-bold leading-tight tabular-nums ${mwDashMoneyClass(stats.totalPnL)}`}
          >
            {formatSignedPnlDisplay(stats.totalPnL)}
          </p>
          <div className="mt-2 h-2.5 w-full">
            <div
              className="h-2.5 rounded-[4px]"
              style={{ width: `${share * 100}%`, backgroundColor: barColor }}
            />
          </div>
          <p className={`mt-1.5 text-[11px] tabular-nums ${mwDashText.tertiary}`}>
            {stats.winRate.toFixed(0)}% WR · {formatCount(stats.totalTrades)}{" "}
            trades
          </p>
          <p className={`mt-0.5 text-[12px] tabular-nums ${mwDashText.muted}`}>
            Avg{" "}
            <span className={mwDashMoneyClass(stats.avgPnL)}>
              {formatSignedPnlDisplay(stats.avgPnL)}
            </span>
          </p>
        </>
      ) : (
        <p className={`text-[13px] ${mwDashText.tertiary}`}>No trades</p>
      )}
    </div>
  )
}

function CompareRow({
  label,
  long,
  short,
  longClass,
  shortClass,
}: {
  label: string
  long: string
  short: string
  longClass?: string
  shortClass?: string
}) {
  return (
    <div className="grid grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)_minmax(0,1fr)] items-baseline gap-2 py-1.5">
      <p className={`text-[12px] ${mwDashText.muted}`}>{label}</p>
      <p
        className={`text-right text-[12px] font-semibold tabular-nums ${
          longClass ?? mwDashText.primary
        }`}
      >
        {long}
      </p>
      <p
        className={`text-right text-[12px] font-semibold tabular-nums ${
          shortClass ?? mwDashText.primary
        }`}
      >
        {short}
      </p>
    </div>
  )
}

function secondaryRows(performance: LongShortPerformance) {
  const { long, short } = performance
  return [
    {
      label: "Best trade",
      long: long?.bestTrade != null ? formatCurrency(long.bestTrade) : "—",
      short: short?.bestTrade != null ? formatCurrency(short.bestTrade) : "—",
      longClass: long?.bestTrade != null ? mwDashText.positive : undefined,
      shortClass: short?.bestTrade != null ? mwDashText.positive : undefined,
    },
    {
      label: "Worst trade",
      long: long?.worstTrade != null ? formatCurrency(long.worstTrade) : "—",
      short: short?.worstTrade != null ? formatCurrency(short.worstTrade) : "—",
      longClass: long?.worstTrade != null ? mwDashText.negative : undefined,
      shortClass: short?.worstTrade != null ? mwDashText.negative : undefined,
    },
    {
      label: "Avg RR",
      long: long ? formatRR(long.avgRR) : "—",
      short: short ? formatRR(short.avgRR) : "—",
    },
    {
      label: "Profit factor",
      long: long ? formatDecimal(long.profitFactor) : "—",
      short: short ? formatDecimal(short.profitFactor) : "—",
      longClass: long
        ? long.profitFactor >= 1
          ? mwDashText.positive
          : mwDashText.negative
        : undefined,
      shortClass: short
        ? short.profitFactor >= 1
          ? mwDashText.positive
          : mwDashText.negative
        : undefined,
    },
    {
      label: "Expectancy",
      long: long ? formatCurrency(long.expectancy) : "—",
      short: short ? formatCurrency(short.expectancy) : "—",
      longClass: long ? mwDashMoneyClass(long.expectancy) : undefined,
      shortClass: short ? mwDashMoneyClass(short.expectancy) : undefined,
    },
    {
      label: "Best win streak",
      long: long ? formatCount(long.bestWinStreak) : "—",
      short: short ? formatCount(short.bestWinStreak) : "—",
    },
  ]
}

function DirectionEdgeRow({ edge }: { edge: DirectionEdge }) {
  const verdictClass =
    edge.verdict === "long"
      ? mwDashText.positive
      : edge.verdict === "short"
        ? mwDashText.accent
        : mwDashText.muted

  return (
    <div className="pt-1">
      <p className={`text-[11px] font-medium uppercase tracking-wide ${mwDashText.tertiary}`}>
        Direction edge
      </p>
      <p className={`mt-1 text-[13px] font-medium leading-snug ${verdictClass}`}>
        {edge.message}
      </p>
      <p className={`mt-1.5 text-[11px] leading-snug ${mwDashText.tertiary}`}>
        Expectancy {edge.longExpectancy == null ? "—" : formatCurrency(edge.longExpectancy)}{" "}
        / {edge.shortExpectancy == null ? "—" : formatCurrency(edge.shortExpectancy)}
        {" · "}
        PF {edge.longProfitFactor == null ? "—" : formatDecimal(edge.longProfitFactor)}{" "}
        / {edge.shortProfitFactor == null ? "—" : formatDecimal(edge.shortProfitFactor)}
      </p>
    </div>
  )
}

export default function MobileWebDashboardLongShort({
  performance,
  totalTrades = 0,
}: MobileWebDashboardLongShortProps) {
  if (totalTrades === 0) {
    return (
      <MobileWebDashboardEmptyCopy body="Close a few trades to compare long and short performance." />
    )
  }

  if (!performance.hasDirectionData) {
    return (
      <MobileWebDashboardEmptyCopy body="Add Long or Short direction on trades to unlock this comparison." />
    )
  }

  const maxAbs = Math.max(
    1,
    Math.abs(performance.long?.totalPnL ?? 0),
    Math.abs(performance.short?.totalPnL ?? 0)
  )

  return (
    <div className="flex flex-col gap-3">
      <div className="flex gap-4">
        <SideColumn
          title="Long"
          swatch="var(--tt-positive, #3ddc97)"
          stats={performance.long}
          maxAbs={maxAbs}
        />
        <SideColumn
          title="Short"
          swatch="var(--tt-accent, #4ec4e0)"
          stats={performance.short}
          maxAbs={maxAbs}
        />
      </div>

      <div className="divide-y divide-[color:color-mix(in_srgb,var(--tt-text)_10%,transparent)]">
        <div className="grid grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)_minmax(0,1fr)] gap-2 pb-1">
          <span />
          <span className={`text-right text-[10px] font-semibold uppercase tracking-wide ${mwDashText.positive}`}>
            Long
          </span>
          <span className={`text-right text-[10px] font-semibold uppercase tracking-wide ${mwDashText.accent}`}>
            Short
          </span>
        </div>
        {secondaryRows(performance).map((row) => (
          <CompareRow key={row.label} {...row} />
        ))}
      </div>

      <DirectionEdgeRow edge={performance.directionEdge} />
    </div>
  )
}
