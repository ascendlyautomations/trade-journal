"use client"

import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
} from "recharts"
import type { ReactNode } from "react"
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import { dashboardWidgetSubtitleClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { chartTooltipStyles } from "@/lib/chartTheme"
import { formatCurrency } from "@/lib/formatCurrency"
import {
  DASHBOARD_SESSION_COLORS,
  DASHBOARD_SESSION_DISPLAY_ORDER,
  type DashboardSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import {
  READABLE_LABEL_CLASS,
  READABLE_PRIMARY_CLASS,
} from "@/lib/readableTextStyles"

function formatNumber(value: number) {
  if (value === null || value === undefined) return "-"
  return value.toLocaleString()
}

export type SessionPiePoint = {
  name: string
  value: number
}

export type SessionBucketStats = {
  totalTrades: number
  wins: number
  totalPnL: number
}

export type SessionBuckets = Record<DashboardSessionBucket, SessionBucketStats>

export type DashboardSessionChartProps = {
  sessionPieData: SessionPiePoint[]
  sessionBuckets: SessionBuckets
  totalTrades?: number
  /**
   * Separate trees so mobile never mounts ResponsiveContainer and desktop
   * never mounts the fixed mobile pie.
   */
  variant?: "mobile" | "desktop"
}

function sessionTitleColor(name: DashboardSessionBucket) {
  if (name === "London") return "text-blue-300"
  if (name === "NY") return "text-emerald-400"
  return "text-purple-300"
}

function sessionDisplayName(name: DashboardSessionBucket) {
  return name === "NY" ? "New York" : name
}

function winRate(stats: SessionBucketStats) {
  return stats.totalTrades ? (stats.wins / stats.totalTrades) * 100 : 0
}

function sessionPieCells(sessionPieData: SessionPiePoint[]) {
  return sessionPieData.map((entry) => (
    <Cell
      key={`cell-${entry.name}`}
      fill={
        DASHBOARD_SESSION_COLORS[entry.name as DashboardSessionBucket] ??
        "#9ca3af"
      }
    />
  ))
}

/** Mobile only: fixed-size pie — never uses ResponsiveContainer. */
function MobileFixedSessionPie({
  sessionPieData,
  size = 120,
}: {
  sessionPieData: SessionPiePoint[]
  size?: number
}) {
  const outerRadius = Math.round(size * 0.43)
  return (
    <PieChart width={size} height={size}>
      <Pie
        data={sessionPieData}
        dataKey="value"
        nameKey="name"
        cx="50%"
        cy="50%"
        outerRadius={outerRadius}
        label={false}
        labelLine={false}
      >
        {sessionPieCells(sessionPieData)}
      </Pie>
      <Tooltip {...chartTooltipStyles} />
    </PieChart>
  )
}

/** Desktop only: ResponsiveContainer sizing (unchanged from prior desktop). */
function DesktopSessionPie({
  sessionPieData,
  height,
  outerRadius,
}: {
  sessionPieData: SessionPiePoint[]
  height: number
  outerRadius: number
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <PieChart>
        <Pie
          data={sessionPieData}
          dataKey="value"
          nameKey="name"
          cx="50%"
          cy="50%"
          outerRadius={outerRadius}
          label={false}
          labelLine={false}
        >
          {sessionPieCells(sessionPieData)}
        </Pie>
        <Tooltip {...chartTooltipStyles} />
      </PieChart>
    </ResponsiveContainer>
  )
}

/** Desktop: 3 session cards in a row (unchanged). */
function SessionBreakdownCards({
  sessionBuckets,
}: {
  sessionBuckets: SessionBuckets
}) {
  return (
    <div className="grid grid-cols-3 gap-1.5 md:gap-3">
      {DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => {
        const s = sessionBuckets[name]
        const wr = winRate(s)
        return (
          <div
            key={name}
            className="rounded-lg border border-white/10 bg-white/5 p-1.5 text-center text-[10px] md:p-3 md:text-sm"
          >
            <p className={`mb-1 font-semibold md:mb-2 ${sessionTitleColor(name)}`}>
              {name}
            </p>
            <p className={READABLE_PRIMARY_CLASS}>
              <span className={READABLE_LABEL_CLASS}>Trades:</span>{" "}
              {formatNumber(s.totalTrades)}
            </p>
            <p className={READABLE_PRIMARY_CLASS}>
              <span className={READABLE_LABEL_CLASS}>Win rate:</span>{" "}
              {wr.toFixed(1)}%
            </p>
            <p
              className={`mt-0.5 text-xs font-semibold tabular-nums md:mt-1 md:text-lg ${
                s.totalPnL >= 0 ? "text-green-400" : "text-red-400"
              }`}
            >
              {formatCurrency(s.totalPnL)}
            </p>
          </div>
        )
      })}
    </div>
  )
}

type SessionDerived = {
  totalTrades: number
  totalPnL: number
  avgPnL: number
  bestSession: DashboardSessionBucket | null
  worstSession: DashboardSessionBucket | null
  bestWinSession: DashboardSessionBucket | null
  bestWinRate: number
}

function deriveSessionSummary(sessionBuckets: SessionBuckets): SessionDerived {
  let totalTrades = 0
  let totalPnL = 0
  let bestSession: DashboardSessionBucket | null = null
  let worstSession: DashboardSessionBucket | null = null
  let bestWinSession: DashboardSessionBucket | null = null
  let bestWinRate = -1

  for (const name of DASHBOARD_SESSION_DISPLAY_ORDER) {
    const s = sessionBuckets[name]
    totalTrades += s.totalTrades
    totalPnL += s.totalPnL

    if (s.totalTrades > 0) {
      if (!bestSession || s.totalPnL > sessionBuckets[bestSession].totalPnL) {
        bestSession = name
      }
      if (!worstSession || s.totalPnL < sessionBuckets[worstSession].totalPnL) {
        worstSession = name
      }
      const wr = winRate(s)
      if (wr > bestWinRate) {
        bestWinRate = wr
        bestWinSession = name
      }
    }
  }

  return {
    totalTrades,
    totalPnL,
    avgPnL: totalTrades ? totalPnL / totalTrades : 0,
    bestSession,
    worstSession,
    bestWinSession,
    bestWinRate: bestWinRate < 0 ? 0 : bestWinRate,
  }
}

function formatSignedCurrency(value: number) {
  const formatted = formatCurrency(value)
  if (value > 0 && !formatted.startsWith("+")) return `+${formatted}`
  return formatted
}

function MobileStatCard({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2">
      <p className="mb-2 text-[9px] font-semibold uppercase tracking-wide text-gray-200">
        {title}
      </p>
      <div className="flex flex-col">{children}</div>
    </div>
  )
}

/** Compact session unit — name header, then value-first metric lines. */
function MobileSessionBlock({
  name,
  stats,
}: {
  name: DashboardSessionBucket
  stats: SessionBucketStats
}) {
  const wr = winRate(stats)
  return (
    <div className="border-b border-white/10 py-2 first:pt-0 last:border-b-0 last:pb-0">
      <div className="mb-1 flex min-w-0 items-center gap-1.5">
        <span
          className="h-1.5 w-1.5 shrink-0 rounded-full"
          style={{ backgroundColor: DASHBOARD_SESSION_COLORS[name] }}
          aria-hidden
        />
        <span
          className={`truncate text-[11px] font-semibold ${sessionTitleColor(name)}`}
        >
          {sessionDisplayName(name)}
        </span>
      </div>
      <div className="space-y-0.5 pl-3">
        <p className="text-[11px] font-semibold tabular-nums leading-snug text-white">
          {formatNumber(stats.totalTrades)} Trades
        </p>
        <p className="text-[11px] font-semibold tabular-nums leading-snug text-white">
          {wr.toFixed(1)}% Win Rate
        </p>
        <p
          className={`text-[11px] font-semibold tabular-nums leading-snug ${
            stats.totalPnL >= 0 ? "text-green-400" : "text-red-400"
          }`}
        >
          {formatSignedCurrency(stats.totalPnL)} P&amp;L
        </p>
      </div>
    </div>
  )
}

/**
 * Volume / Edge metric unit — stacked title → context → value.
 * Tight spacing inside the group; separators create hierarchy between groups.
 */
function MobileMetricUnit({
  title,
  context,
  value,
  valueClass,
  swatch,
}: {
  title: string
  context?: string | null
  value: string
  valueClass?: string
  swatch?: string
}) {
  return (
    <div className="border-b border-white/10 py-2 first:pt-0 last:border-b-0 last:pb-0">
      <div className="mb-0.5 flex min-w-0 items-center gap-1.5">
        {swatch ? (
          <span
            className="h-1.5 w-1.5 shrink-0 rounded-full"
            style={{ backgroundColor: swatch }}
            aria-hidden
          />
        ) : null}
        <p className="text-[10px] font-medium leading-snug text-gray-200">
          {title}
        </p>
      </div>
      <div className="space-y-0.5">
        {context ? (
          <p className="text-[11px] font-semibold leading-snug text-white">
            {context}
          </p>
        ) : null}
        <p
          className={`text-[11px] font-semibold tabular-nums leading-snug text-white ${valueClass ?? ""}`}
        >
          {value}
        </p>
      </div>
    </div>
  )
}

/**
 * Mobile: CSS Grid ~65/35. Fixed-size pie (no ResponsiveContainer).
 * Sessions stays solo; Volume + Edge share one denser supporting card.
 */
function MobileSessionSplitLayout({
  sessionPieData,
  sessionBuckets,
}: {
  sessionPieData: SessionPiePoint[]
  sessionBuckets: SessionBuckets
}) {
  const summary = deriveSessionSummary(sessionBuckets)

  const volumeColumn = (
    <>
      <MobileMetricUnit
        title="Total Trades"
        value={formatNumber(summary.totalTrades)}
      />
      <MobileMetricUnit
        title="Best Session"
        context={
          summary.bestSession
            ? sessionDisplayName(summary.bestSession)
            : null
        }
        value={
          summary.bestSession
            ? formatSignedCurrency(
                sessionBuckets[summary.bestSession].totalPnL
              )
            : "—"
        }
        valueClass={
          summary.bestSession &&
          sessionBuckets[summary.bestSession].totalPnL >= 0
            ? "text-green-400"
            : summary.bestSession
              ? "text-red-400"
              : undefined
        }
        swatch={
          summary.bestSession
            ? DASHBOARD_SESSION_COLORS[summary.bestSession]
            : undefined
        }
      />
      <MobileMetricUnit
        title="Worst Session"
        context={
          summary.worstSession
            ? sessionDisplayName(summary.worstSession)
            : null
        }
        value={
          summary.worstSession
            ? formatSignedCurrency(
                sessionBuckets[summary.worstSession].totalPnL
              )
            : "—"
        }
        valueClass={
          summary.worstSession &&
          sessionBuckets[summary.worstSession].totalPnL >= 0
            ? "text-green-400"
            : summary.worstSession
              ? "text-red-400"
              : undefined
        }
        swatch={
          summary.worstSession
            ? DASHBOARD_SESSION_COLORS[summary.worstSession]
            : undefined
        }
      />
    </>
  )

  const edgeColumn = (
    <>
      <MobileMetricUnit
        title="Best Win %"
        context={
          summary.bestWinSession
            ? sessionDisplayName(summary.bestWinSession)
            : null
        }
        value={
          summary.bestWinSession
            ? `${summary.bestWinRate.toFixed(1)}%`
            : "—"
        }
        swatch={
          summary.bestWinSession
            ? DASHBOARD_SESSION_COLORS[summary.bestWinSession]
            : undefined
        }
      />
      <MobileMetricUnit
        title="Avg P&L"
        value={formatSignedCurrency(summary.avgPnL)}
        valueClass={
          summary.avgPnL >= 0 ? "text-green-400" : "text-red-400"
        }
      />
      <MobileMetricUnit
        title="Total P&L"
        value={formatSignedCurrency(summary.totalPnL)}
        valueClass={
          summary.totalPnL >= 0 ? "text-green-400" : "text-red-400"
        }
      />
    </>
  )

  return (
    <div
      className="w-full"
      style={{
        display: "grid",
        gridTemplateColumns: "1.85fr 1fr",
        alignItems: "center",
        columnGap: "0.5rem",
      }}
    >
      <div className="flex min-w-0 flex-col gap-2">
        <MobileStatCard title="Sessions">
          {DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => (
            <MobileSessionBlock
              key={name}
              name={name}
              stats={sessionBuckets[name]}
            />
          ))}
        </MobileStatCard>

        <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2">
          <div className="grid grid-cols-2 items-center gap-0">
            <div className="min-w-0 self-center pr-2">
              <p className="mb-2 text-[9px] font-semibold uppercase tracking-wide text-gray-200">
                Volume
              </p>
              <div className="flex flex-col">{volumeColumn}</div>
            </div>
            <div className="min-w-0 self-center border-l border-white/10 pl-2">
              <p className="mb-2 text-[9px] font-semibold uppercase tracking-wide text-gray-200">
                Edge
              </p>
              <div className="flex flex-col">{edgeColumn}</div>
            </div>
          </div>
        </div>
      </div>

      <div className="flex min-w-0 items-center justify-center self-stretch">
        <MobileFixedSessionPie sessionPieData={sessionPieData} size={120} />
      </div>
    </div>
  )
}

export default function DashboardSessionChart({
  sessionPieData,
  sessionBuckets,
  totalTrades = 0,
  variant = "desktop",
}: DashboardSessionChartProps) {
  const showEmpty = totalTrades === 0
  const isMobile = variant === "mobile"

  const DESKTOP_PIE_HEIGHT = 240
  const DESKTOP_PIE_RADIUS = 88

  return (
    <div
      className={`flex h-full min-h-[260px] flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:min-h-[300px] md:p-4 ${
        isMobile
          ? "h-auto min-h-0 px-2 pb-1.5 pt-1.5"
          : ""
      }`}
    >
      <h2
        className={`mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base ${
          isMobile ? "mb-1" : ""
        }`}
      >
        Session Performance
      </h2>
      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : isMobile ? (
        <MobileSessionSplitLayout
          sessionPieData={sessionPieData}
          sessionBuckets={sessionBuckets}
        />
      ) : (
        <div className="flex flex-1 flex-col gap-4">
          <div className="flex min-h-[240px] flex-col">
            <p className={dashboardWidgetSubtitleClass}>Trades by Session</p>
            <div className="min-h-0 w-full flex-1 overflow-hidden">
              <DesktopSessionPie
                sessionPieData={sessionPieData}
                height={DESKTOP_PIE_HEIGHT}
                outerRadius={DESKTOP_PIE_RADIUS}
              />
            </div>
          </div>
          <div className="flex flex-col">
            <p className={dashboardWidgetSubtitleClass}>Session breakdown</p>
            <SessionBreakdownCards sessionBuckets={sessionBuckets} />
          </div>
        </div>
      )}
    </div>
  )
}
