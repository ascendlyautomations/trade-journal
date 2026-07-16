import Link from "next/link"
import type { ReactNode } from "react"
import {
  dashboardInsightMetricNegativeClass,
  dashboardInsightMetricNeutralClass,
  dashboardInsightMetricPositiveClass,
  dashboardWidgetSectionTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import { cn } from "@/app/components/ui/cn"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import type { PeriodTradeStats } from "@/lib/periodTradeStats"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"

type MetricTone = "positive" | "negative" | "neutral"

function toneForSigned(value: number | null | undefined): MetricTone | undefined {
  if (value == null || !Number.isFinite(value) || value === 0) return undefined
  return value > 0 ? "positive" : "negative"
}

function MetricRow({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: MetricTone
}) {
  const valueClass =
    tone === "positive"
      ? dashboardInsightMetricPositiveClass
      : tone === "negative"
        ? dashboardInsightMetricNegativeClass
        : dashboardInsightMetricNeutralClass

  return (
    <div className="flex min-w-0 items-baseline justify-between gap-2">
      <span className="truncate text-[11px] text-gray-400 md:text-xs">{label}</span>
      <span className={cn(valueClass, "shrink-0 tabular-nums text-[11px] md:text-xs")}>
        {value}
      </span>
    </div>
  )
}

function Section({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <div>
      <h4 className={cn(dashboardWidgetSectionTitleClass, "mb-1.5")}>{title}</h4>
      <div className="grid grid-cols-2 gap-x-3 gap-y-1">{children}</div>
    </div>
  )
}

function formatMoney(value: number | null | undefined, formatPNL: (n: number) => string) {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPNL(value)
}

function formatCount(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value)) return "—"
  return String(Math.round(value))
}

function formatPct(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value)) return "—"
  return `${value.toFixed(1)}%`
}

function formatProfitFactor(stats: PeriodTradeStats) {
  if (stats.profitFactorInfinite) return "∞"
  if (stats.profitFactor == null || !Number.isFinite(stats.profitFactor)) return "—"
  if (stats.profitFactor === 0 && stats.winningTrades === 0) return "—"
  return formatDecimal(stats.profitFactor, 2)
}

function formatContracts(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatDecimal(value, 2)
}

export default function CalendarMonthlyStats({
  stats,
  formatPNL,
  hasAnyTrades,
}: {
  stats: PeriodTradeStats
  formatPNL: (value: number) => string
  hasAnyTrades: boolean
}) {
  if (stats.totalTrades === 0) {
    return (
      <div className="space-y-2 text-sm">
        <p className="text-gray-400">
          {hasAnyTrades ? "No trades this month" : "No trades yet"}
        </p>
        {!hasAnyTrades ? (
          <Link
            href="/app"
            className="inline-block text-sm font-medium text-blue-300 hover:text-blue-200"
          >
            Add Trade →
          </Link>
        ) : null}
      </div>
    )
  }

  const money = (value: number | null | undefined) => formatMoney(value, formatPNL)
  const holdLabel =
    stats.avgHoldSeconds != null
      ? formatHoldDurationSeconds(Math.round(stats.avgHoldSeconds)) ?? "—"
      : "—"

  return (
    <div className="max-h-[min(28rem,55vh)] space-y-3 overflow-y-auto pr-0.5 [scrollbar-width:thin]">
      <Section title="Performance">
        <MetricRow label="Total Trades" value={formatCount(stats.totalTrades)} />
        <MetricRow label="Win Rate" value={formatPct(stats.winRate)} />
        <MetricRow label="Winning" value={formatCount(stats.winningTrades)} />
        <MetricRow label="Losing" value={formatCount(stats.losingTrades)} />
        <MetricRow
          label="Total P&L"
          value={money(stats.totalPnl)}
          tone={toneForSigned(stats.totalPnl)}
        />
        <MetricRow
          label="Avg Daily P&L"
          value={money(stats.consistency.avgDailyPnl)}
          tone={toneForSigned(stats.consistency.avgDailyPnl)}
        />
        <MetricRow
          label="Avg Trade P&L"
          value={money(stats.avgTradePnl)}
          tone={toneForSigned(stats.avgTradePnl)}
        />
        <MetricRow
          label="Best Trade"
          value={money(stats.bestTrade)}
          tone={toneForSigned(stats.bestTrade)}
        />
        <MetricRow
          label="Worst Trade"
          value={money(stats.worstTrade)}
          tone={toneForSigned(stats.worstTrade)}
        />
      </Section>

      <Section title="Risk">
        <MetricRow label="Profit Factor" value={formatProfitFactor(stats)} />
        <MetricRow label="Avg RR" value={formatRR(stats.avgRR)} />
        <MetricRow label="Total RR" value={formatRR(stats.totalRR)} />
        <MetricRow
          label="Avg Win"
          value={money(stats.avgWin)}
          tone={toneForSigned(stats.avgWin)}
        />
        <MetricRow
          label="Avg Loss"
          value={money(stats.avgLoss)}
          tone={toneForSigned(stats.avgLoss)}
        />
        <MetricRow
          label="Largest Win"
          value={money(stats.largestWin)}
          tone={toneForSigned(stats.largestWin)}
        />
        <MetricRow
          label="Largest Loss"
          value={money(stats.largestLoss)}
          tone={toneForSigned(stats.largestLoss)}
        />
      </Section>

      <Section title="Execution">
        <MetricRow
          label="Long Trades"
          value={stats.hasDirectionData ? formatCount(stats.longTrades) : "—"}
        />
        <MetricRow
          label="Short Trades"
          value={stats.hasDirectionData ? formatCount(stats.shortTrades) : "—"}
        />
        <MetricRow label="Avg Hold" value={holdLabel} />
        <MetricRow
          label="Avg Contracts"
          value={stats.hasContractData ? formatContracts(stats.avgContracts) : "—"}
        />
        <MetricRow
          label="Total Contracts"
          value={
            stats.hasContractData ? formatContracts(stats.totalContracts) : "—"
          }
        />
      </Section>

      <Section title="Consistency">
        <MetricRow
          label="Green Days"
          value={formatCount(stats.consistency.greenDays)}
          tone={stats.consistency.greenDays > 0 ? "positive" : undefined}
        />
        <MetricRow
          label="Red Days"
          value={formatCount(stats.consistency.redDays)}
          tone={stats.consistency.redDays > 0 ? "negative" : undefined}
        />
        <MetricRow
          label="Break-even"
          value={formatCount(stats.consistency.breakEvenDays)}
        />
        <MetricRow
          label="Best Day"
          value={money(stats.consistency.bestDayPnl)}
          tone={toneForSigned(stats.consistency.bestDayPnl)}
        />
        <MetricRow
          label="Worst Day"
          value={money(stats.consistency.worstDayPnl)}
          tone={toneForSigned(stats.consistency.worstDayPnl)}
        />
        <MetricRow
          label="Win Streak"
          value={formatCount(stats.longestWinStreak)}
        />
        <MetricRow
          label="Loss Streak"
          value={formatCount(stats.longestLossStreak)}
        />
      </Section>
    </div>
  )
}
