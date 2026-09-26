"use client"

import { useState, type ReactNode } from "react"
import { Lightbulb, TriangleAlert, Trophy } from "lucide-react"
import DashboardRecentTrades from "@/app/components/dashboard/DashboardRecentTrades"
import type { DashboardTradeRow } from "@/app/components/dashboard/dashboardTypes"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"
import type { HoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import type {
  DirectionEdge,
  LongShortPerformance,
  LongShortSideStats,
} from "@/lib/dashboardLongShortStats"
import { useTradingReports } from "@/lib/useTradingReports"
import type { TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"

const SYMBOL_PREVIEW = 6

const REPORT_PERIODS: TradingReportPeriodKey[] = [
  "weekly_this",
  "weekly_last",
  "monthly_this",
  "monthly_last",
]

type SymbolRow = {
  ticker: string
  totalTrades: number
  winRate: number
  totalPnL: number
}

type BestSetup = {
  strategy: string
  trades: number
  winRate: number
  totalPnL: number
} | null

type InsightCard = {
  key: string
  title: string
  body: string
  metric?: string
  tone: "default" | "positive" | "negative"
}

export type DashboardDesktopLowerProps = {
  userId: string
  reportTrades: DashboardTradeRow[]
  onOpenReportPeriod: (key: TradingReportPeriodKey) => void
  symbolPerformanceRows: SymbolRow[]
  hasAnyTrades: boolean
  longShortPerformance: LongShortPerformance
  holdTimeStats: HoldTimeStats
  totalTrades: number
  showInsights: boolean
  showBestSetup: boolean
  showWorstSetup: boolean
  showWarnings: boolean
  insights: string[]
  combinedInsights: string[]
  worstInsight: string | null
  warnings: string[]
  insightBestSymbol: string | null
  insightBestSymbolAvg: number
  insightBestWeekday: string | null
  insightBestWeekdayAvg: number
  bestSetup: BestSetup
  recentTrades: DashboardTradeRow[]
  onSelectTrade: (trade: DashboardTradeRow) => void
}

function pnlClass(value: number) {
  if (value > 0) return "text-green-400"
  if (value < 0) return "text-red-400"
  return "text-white"
}

function Panel({
  title,
  children,
  className = "",
}: {
  title: string
  children: ReactNode
  className?: string
}) {
  return (
    <section
      className={`rounded-xl border border-white/10 bg-white/10 p-4 ${className}`.trim()}
    >
      <h3 className="mb-3 text-sm font-semibold text-white">{title}</h3>
      {children}
    </section>
  )
}

function formatDuration(seconds: number | null | undefined) {
  if (seconds == null) return "—"
  return formatHoldDurationSeconds(Math.round(seconds)) ?? "—"
}

function insightTitle(text: string) {
  if (text.includes("session")) return "Strongest session"
  if (text.includes("most profitable market")) return "Best market"
  if (text.includes("going ")) return "Direction"
  return "Performance"
}

function buildInsightCards(props: DashboardDesktopLowerProps): InsightCard[] {
  const cards: InsightCard[] = []
  const mentioned = props.insights.join(" ").toLowerCase()

  if (props.showInsights) {
    props.insights.forEach((text, index) => {
      cards.push({
        key: `insight-${index}`,
        title: insightTitle(text),
        body: text,
        tone: "default",
      })
    })
    if (
      props.insightBestSymbol &&
      !mentioned.includes(props.insightBestSymbol.toLowerCase())
    ) {
      cards.push({
        key: "symbol",
        title: "Best symbol",
        body: `${props.insightBestSymbol} has the strongest average result in this set.`,
        metric: formatCurrency(props.insightBestSymbolAvg),
        tone: props.insightBestSymbolAvg >= 0 ? "positive" : "negative",
      })
    }
    if (
      props.insightBestWeekday &&
      !mentioned.includes(props.insightBestWeekday.toLowerCase())
    ) {
      cards.push({
        key: "weekday",
        title: "Best weekday",
        body: `${props.insightBestWeekday} is the strongest day in this set.`,
        metric: formatCurrency(props.insightBestWeekdayAvg),
        tone: props.insightBestWeekdayAvg >= 0 ? "positive" : "negative",
      })
    }
    props.combinedInsights.forEach((text, index) => {
      cards.push({
        key: `combo-${index}`,
        title: "Combined edge",
        body: text,
        tone: "positive",
      })
    })
  }

  if (props.showBestSetup && props.bestSetup) {
    cards.push({
      key: "setup",
      title: "Best strategy",
      body: `${props.bestSetup.strategy} is the strongest tagged strategy.`,
      metric: `${props.bestSetup.winRate.toFixed(0)}% · ${formatCurrency(props.bestSetup.totalPnL)} · ${props.bestSetup.trades} trades`,
      tone: props.bestSetup.totalPnL >= 0 ? "positive" : "negative",
    })
  }

  if (props.showWorstSetup && props.worstInsight) {
    cards.push({
      key: "risk",
      title: "Risk",
      body: props.worstInsight,
      tone: "negative",
    })
  }

  if (props.showWarnings) {
    props.warnings.forEach((text, index) => {
      cards.push({
        key: `warn-${index}`,
        title: "Warning",
        body: text,
        tone: "negative",
      })
    })
  }

  return cards
}

function SymbolPanel({ rows }: { rows: SymbolRow[] }) {
  const [expanded, setExpanded] = useState(false)
  const visible = expanded ? rows : rows.slice(0, SYMBOL_PREVIEW)
  const max = Math.max(1, ...rows.map((row) => Math.abs(row.totalPnL)))
  const hiddenCount = rows.length - SYMBOL_PREVIEW

  if (rows.length === 0) {
    return <p className="text-sm text-gray-400">No symbol results for this filter.</p>
  }

  return (
    <div>
      {visible.map((row) => {
        const width =
          row.totalPnL === 0
            ? 0
            : Math.max(6, (Math.abs(row.totalPnL) / max) * 100)
        return (
          <div
            key={row.ticker}
            className="grid grid-cols-[5.5rem_minmax(0,1fr)_auto] items-center gap-3 border-b border-white/10 py-2 last:border-b-0"
          >
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-white">{row.ticker}</p>
              <p className="truncate text-[11px] text-gray-400">
                {row.totalTrades} · {row.winRate.toFixed(0)}%
              </p>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-black/20">
              <div
                className={`h-full rounded-full ${row.totalPnL >= 0 ? "tt-dash-bar-pos" : "tt-dash-bar-neg"}`}
                style={{ width: `${Math.min(100, width)}%` }}
              />
            </div>
            <span className={`text-sm font-semibold tabular-nums ${pnlClass(row.totalPnL)}`}>
              {formatCurrency(row.totalPnL)}
            </span>
          </div>
        )
      })}
      {hiddenCount > 0 ? (
        <button
          type="button"
          onClick={() => setExpanded((open) => !open)}
          className="mt-2 text-xs text-blue-300 hover:text-blue-200"
        >
          {expanded ? "Show less" : `Show ${hiddenCount} more`}
        </button>
      ) : null}
    </div>
  )
}

function sideValue(
  side: LongShortSideStats | null,
  read: (side: LongShortSideStats) => string,
  tone?: (side: LongShortSideStats) => string
) {
  if (!side) return { text: "—", className: "text-gray-400" }
  return { text: read(side), className: tone ? tone(side) : "text-white" }
}

function DirectionPanel({ performance }: { performance: LongShortPerformance }) {
  const edge: DirectionEdge = performance.directionEdge
  const rows: {
    label: string
    long: { text: string; className: string }
    short: { text: string; className: string }
  }[] = [
    {
      label: "P&L",
      long: sideValue(performance.long, (side) => formatCurrency(side.totalPnL), (side) => pnlClass(side.totalPnL)),
      short: sideValue(performance.short, (side) => formatCurrency(side.totalPnL), (side) => pnlClass(side.totalPnL)),
    },
    {
      label: "Win rate",
      long: sideValue(performance.long, (side) => `${side.winRate.toFixed(0)}%`),
      short: sideValue(performance.short, (side) => `${side.winRate.toFixed(0)}%`),
    },
    {
      label: "Profit factor",
      long: sideValue(
        performance.long,
        (side) => formatDecimal(side.profitFactor),
        (side) => (side.profitFactor >= 1 ? "text-green-400" : "text-red-400")
      ),
      short: sideValue(
        performance.short,
        (side) => formatDecimal(side.profitFactor),
        (side) => (side.profitFactor >= 1 ? "text-green-400" : "text-red-400")
      ),
    },
    {
      label: "Avg P&L",
      long: sideValue(performance.long, (side) => formatCurrency(side.avgPnL), (side) => pnlClass(side.avgPnL)),
      short: sideValue(performance.short, (side) => formatCurrency(side.avgPnL), (side) => pnlClass(side.avgPnL)),
    },
    {
      label: "Avg RR",
      long: sideValue(performance.long, (side) => formatRR(side.avgRR)),
      short: sideValue(performance.short, (side) => formatRR(side.avgRR)),
    },
    {
      label: "Trades",
      long: sideValue(performance.long, (side) => side.totalTrades.toLocaleString()),
      short: sideValue(performance.short, (side) => side.totalTrades.toLocaleString()),
    },
  ]

  if (!performance.hasDirectionData) {
    return <p className="text-sm text-gray-400">Add a direction to compare long and short.</p>
  }

  return (
    <div>
      <div className="grid grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)] gap-x-3 border-b border-white/10 pb-2 text-[11px] uppercase tracking-wide text-gray-400">
        <span />
        <span className="text-right text-green-400">Long</span>
        <span className="text-right text-blue-300">Short</span>
      </div>
      {rows.map((row) => (
        <div
          key={row.label}
          className="grid grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)] gap-x-3 border-b border-white/10 py-1.5 text-sm last:border-b-0"
        >
          <span className="text-gray-300">{row.label}</span>
          <span className={`text-right font-semibold tabular-nums ${row.long.className}`}>
            {row.long.text}
          </span>
          <span className={`text-right font-semibold tabular-nums ${row.short.className}`}>
            {row.short.text}
          </span>
        </div>
      ))}
      {edge.message ? (
        <p className="mt-3 text-sm leading-snug text-gray-200">{edge.message}</p>
      ) : null}
    </div>
  )
}

function HoldDetail({ stats, totalTrades }: { stats: HoldTimeStats; totalTrades: number }) {
  const extremes = [
    { label: "Fastest winner", extreme: stats.fastestWinner, tone: "text-green-400" },
    { label: "Longest winner", extreme: stats.longestWinner, tone: "text-green-400" },
    { label: "Fastest loser", extreme: stats.fastestLoser, tone: "text-red-400" },
    { label: "Longest loser", extreme: stats.longestLoser, tone: "text-red-400" },
  ]

  if (totalTrades === 0 || !stats.hasDurationData) {
    return (
      <p className="text-sm text-gray-400">
        Duration extremes appear once trades include an entry and exit.
      </p>
    )
  }

  return (
    <div>
      <p className="mb-3 text-[11px] text-gray-400">
        {stats.tradesWithDuration} trades with a duration
      </p>
      <div className="grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4">
        {extremes.map((row) => (
          <div key={row.label} className="min-w-0 border-t border-white/10 pt-2">
            <p className="text-[11px] text-gray-400">{row.label}</p>
            <p className="text-sm font-semibold tabular-nums text-white">
              {formatDuration(row.extreme?.durationSeconds)}
            </p>
            {row.extreme ? (
              <p className={`text-sm font-semibold tabular-nums ${row.tone}`}>
                {formatCurrency(row.extreme.pnl)}
              </p>
            ) : null}
          </div>
        ))}
      </div>
    </div>
  )
}

function ReportsPanel({
  userId,
  trades,
  onOpenPeriod,
}: {
  userId: string
  trades: DashboardTradeRow[]
  onOpenPeriod: (key: TradingReportPeriodKey) => void
}) {
  const { snapshot, loading } = useTradingReports(userId, trades)

  return (
    <section className="rounded-xl border border-white/10 bg-white/10 p-4">
      <h3 className="mb-3 text-sm font-semibold text-white">Trading Reports</h3>
      {loading && !snapshot ? (
        <p className="text-sm text-gray-400">Preparing reports…</p>
      ) : (
        <div>
          {REPORT_PERIODS.map((key) => {
            const report = snapshot?.reports[key]
            const pnl = report?.metrics.netPnl ?? 0
            return (
              <button
                key={key}
                type="button"
                onClick={() => onOpenPeriod(key)}
                className="flex w-full items-center justify-between gap-3 border-b border-white/10 py-2 text-left last:border-b-0 hover:bg-white/5"
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-medium text-white">
                    {report?.title ?? "Report"}
                  </span>
                  <span className="block truncate text-[11px] text-gray-400">
                    {report
                      ? `${report.dateRangeLabel} · ${report.metrics.tradesTaken} trades · ${report.metrics.winRate.toFixed(0)}%`
                      : "Open report"}
                  </span>
                </span>
                <span className={`shrink-0 text-sm font-semibold tabular-nums ${report ? pnlClass(pnl) : "text-gray-400"}`}>
                  {report ? formatCurrency(pnl) : "—"}
                </span>
              </button>
            )
          })}
        </div>
      )}
    </section>
  )
}

function InsightIcon({ tone }: { tone: InsightCard["tone"] }) {
  if (tone === "negative") {
    return <TriangleAlert className="h-3.5 w-3.5 text-red-400" aria-hidden />
  }
  if (tone === "positive") {
    return <Trophy className="h-3.5 w-3.5 text-green-400" aria-hidden />
  }
  return <Lightbulb className="h-3.5 w-3.5 text-blue-300" aria-hidden />
}

export default function DashboardDesktopLower(props: DashboardDesktopLowerProps) {
  const cards = buildInsightCards(props)

  return (
    <div className="tt-dash-desktop-v1">
      <section>
        <h2 className="tt-dash-section-title">Deeper Analytics</h2>
        <p className="tt-dash-section-subtitle mb-3">
          Dig into the details behind your performance.
        </p>
        <div className="tt-dash-deeper">
          <Panel title="Symbol Performance" className="tt-dash-deeper-symbol">
            <SymbolPanel rows={props.symbolPerformanceRows} />
          </Panel>
          <Panel title="Direction Detail">
            <DirectionPanel performance={props.longShortPerformance} />
          </Panel>
          <Panel title="Hold Time Detail" className="tt-dash-deeper-hold">
            <HoldDetail stats={props.holdTimeStats} totalTrades={props.totalTrades} />
          </Panel>
        </div>
      </section>

      <section>
        <h2 className="tt-dash-section-title">Insights</h2>
        <p className="tt-dash-section-subtitle mb-3">
          What your trading data is telling you.
        </p>
        {cards.length === 0 ? (
          <p className="text-sm text-gray-400">
            Not enough sample size yet for a filtered insight.
          </p>
        ) : (
          <div className="tt-dash-insights-grid">
            {cards.map((card, index) => (
              <article
                key={card.key}
                className={`rounded-xl border border-white/10 bg-white/10 p-3 ${
                  index === 0 ? "tt-dash-insight-lead" : ""
                }`}
              >
                <div className="mb-1.5 flex items-center gap-2">
                  <InsightIcon tone={card.tone} />
                  <h3 className="text-sm font-semibold text-white">{card.title}</h3>
                </div>
                <p className="text-sm leading-snug text-gray-200">{card.body}</p>
                {card.metric ? (
                  <p
                  className={`mt-2 text-sm font-semibold tabular-nums ${
                    card.tone === "negative"
                      ? "text-red-400"
                      : card.tone === "positive"
                        ? "text-green-400"
                        : "text-white"
                  }`}
                >
                    {card.metric}
                  </p>
                ) : null}
              </article>
            ))}
          </div>
        )}
      </section>

      <section>
        <h2 className="tt-dash-section-title">Journal</h2>
        <p className="tt-dash-section-subtitle mb-3">
          Recent trades and how performance has changed.
        </p>
        <div className="tt-dash-journal">
          <DashboardRecentTrades
            presentation="journal"
            trades={props.recentTrades}
            hasAnyTrades={props.hasAnyTrades}
            onSelectTrade={props.onSelectTrade}
            viewAllHref="/trades"
          />
          <ReportsPanel
            userId={props.userId}
            trades={props.reportTrades}
            onOpenPeriod={props.onOpenReportPeriod}
          />
        </div>
      </section>
    </div>
  )
}
