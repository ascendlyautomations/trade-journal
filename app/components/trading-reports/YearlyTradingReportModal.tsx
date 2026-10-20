"use client"

import "./tradingReportLight.css"
import DashboardEquityCurve from "@/app/components/dashboard/DashboardEquityCurve"
import TradingReportModal from "@/app/components/trading-reports/TradingReportModal"
import Modal from "@/app/components/ui/Modal"
import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import {
  availableTradingReportYears,
  generateYearMonthTradingReport,
  generateYearlyTradingReport,
} from "@/lib/tradingReports/generateYearlyTradingReport"
import type { TradingYearlyReport } from "@/lib/tradingReports/tradingYearlyReportTypes"
import { useEffect, useMemo, useState } from "react"
import type { TradingReport } from "@/lib/tradingReports/tradingReportTypes"

type YearlyTradingReportModalProps = {
  open: boolean
  onClose: () => void
  trades: any[]
  initialYear: number | null
  onYearChange?: (year: number | null) => void
  viewerUserId?: string | null
  onViewTrade: (trade: { id?: string | null }) => void
}

function MetricCell({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: "profit" | "loss" | "neutral"
}) {
  const valueClass =
    tone === "profit"
      ? "text-emerald-300"
      : tone === "loss"
        ? "text-red-300"
        : "text-white"
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 p-3">
      <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
        {label}
      </p>
      <p
        className={`mt-1 text-sm font-semibold tabular-nums md:text-base ${valueClass}`}
      >
        {value}
      </p>
    </div>
  )
}

function formatOptionalMoney(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPnlCurrency(value)
}

function formatOptionalDecimal(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return value.toFixed(2)
}

function YearlyReportBody({
  report,
  onOpenMonth,
  onBack,
  showYearPicker,
  years,
  year,
  onSelectYear,
}: {
  report: TradingYearlyReport
  onOpenMonth: (month: number) => void
  onBack: () => void
  showYearPicker: boolean
  years: number[]
  year: number
  onSelectYear: (y: number) => void
}) {
  const m = report.metrics
  const maxBar = Math.max(
    ...report.monthlyPnLBars.map((b) => Math.abs(b.value)),
    1
  )

  return (
    <div className="space-y-6">
      <header className="space-y-2 border-b border-white/10 pb-4 pr-12">
        {showYearPicker ? (
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={onBack}
              className="text-xs font-medium text-blue-300 underline"
            >
              All years
            </button>
            <div className="flex flex-wrap gap-2">
              {years.map((y) => (
                <button
                  key={y}
                  type="button"
                  onClick={() => onSelectYear(y)}
                  className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition md:text-sm ${
                    y === year
                      ? "border-blue-400/60 bg-blue-500/20 text-white"
                      : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
                  }`}
                >
                  {y}
                </button>
              ))}
            </div>
          </div>
        ) : null}
        <p className="text-xs font-medium uppercase tracking-wider text-blue-300">
          Yearly Performance Report
        </p>
        <h2 className="text-xl font-semibold text-white md:text-2xl">
          {report.title}
        </h2>
        <p className="text-sm text-gray-400">{report.dateRangeLabel}</p>
      </header>

      <section
        className={`${dashboardInsightCardClass} space-y-2 bg-gradient-to-br from-blue-500/10 to-white/5`}
      >
        <p className="text-sm leading-relaxed text-gray-300">
          {report.executiveSummary}
        </p>
      </section>

      <section className="space-y-3">
        <h3 className="text-sm font-semibold text-white">Year Summary</h3>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
          <MetricCell
            label="Net P&L"
            value={formatPnlCurrency(m.netPnl)}
            tone={m.netPnl > 0 ? "profit" : m.netPnl < 0 ? "loss" : "neutral"}
          />
          <MetricCell label="Total Trades" value={String(m.tradeCount)} />
          <MetricCell
            label="Win Rate"
            value={m.winRate != null ? `${m.winRate.toFixed(1)}%` : "—"}
          />
          <MetricCell
            label="Profit Factor"
            value={formatOptionalDecimal(m.profitFactor)}
          />
          <MetricCell
            label="Average Winner"
            value={formatOptionalMoney(m.averageWinner)}
          />
          <MetricCell
            label="Average Loser"
            value={formatOptionalMoney(m.averageLoser)}
          />
          <MetricCell
            label="Average RR"
            value={m.averageRr != null ? formatRR(m.averageRr) : "—"}
          />
          <MetricCell
            label="Expectancy"
            value={formatOptionalMoney(m.expectancy)}
          />
          <MetricCell
            label="Best Trade"
            value={formatOptionalMoney(m.bestTrade)}
          />
          <MetricCell
            label="Worst Trade"
            value={formatOptionalMoney(m.worstTrade)}
          />
          <MetricCell
            label="Best Day"
            value={
              m.bestDayLabel
                ? `${m.bestDayLabel} (${formatOptionalMoney(m.bestDayPnl)})`
                : "—"
            }
          />
          <MetricCell
            label="Worst Day"
            value={
              m.worstDayLabel
                ? `${m.worstDayLabel} (${formatOptionalMoney(m.worstDayPnl)})`
                : "—"
            }
          />
          <MetricCell
            label="Max Drawdown"
            value={formatPnlCurrency(m.maxDrawdown)}
          />
          <MetricCell label="Winning Days" value={String(m.winningDays)} />
          <MetricCell label="Losing Days" value={String(m.losingDays)} />
        </div>
      </section>

      <section className={`${dashboardInsightCardClass} space-y-3`}>
        <h3 className="text-sm font-semibold text-white">Cumulative P&L</h3>
        {report.equityCurve.length === 0 ? (
          <p className="text-sm text-gray-400">
            Log trades this year to unlock your equity curve.
          </p>
        ) : (
          <DashboardEquityCurve data={report.equityCurve} variant="desktop" />
        )}
      </section>

      {report.monthlyPnLBars.length > 0 ? (
        <section className={`${dashboardInsightCardClass} space-y-3`}>
          <h3 className="text-sm font-semibold text-white">Monthly P&L</h3>
          <div className="flex items-end gap-1 sm:gap-2">
            {report.monthlyPnLBars.map((bar) => {
              const heightPct = Math.max(
                4,
                (Math.abs(bar.value) / maxBar) * 100
              )
              const positive = bar.value >= 0
              return (
                <div
                  key={bar.label}
                  className="flex min-w-0 flex-1 flex-col items-center gap-1"
                >
                  <div
                    className="flex h-24 w-full items-end justify-center sm:h-28"
                    title={`${bar.label}: ${formatPnlCurrency(bar.value)}`}
                  >
                    <div
                      className={`w-full max-w-[2rem] rounded-t ${positive ? "bg-emerald-500/70" : "bg-red-500/70"}`}
                      style={{ height: `${heightPct}%` }}
                    />
                  </div>
                  <span className="text-[10px] text-gray-400 sm:text-xs">
                    {bar.label}
                  </span>
                </div>
              )
            })}
          </div>
        </section>
      ) : null}

      <section className={`${dashboardInsightCardClass} space-y-2`}>
        <h3 className="text-sm font-semibold text-white">Win / Loss</h3>
        <p className="text-sm text-gray-300">
          <span className="font-semibold text-emerald-300">{m.winCount}</span>{" "}
          wins ·{" "}
          <span className="font-semibold text-red-300">{m.lossCount}</span>{" "}
          losses
        </p>
      </section>

      {report.strongestMonth || report.weakestMonth ? (
        <section className={`${dashboardInsightCardClass} space-y-2`}>
          <h3 className="text-sm font-semibold text-white">
            Strongest / Weakest Month
          </h3>
          {report.strongestMonth ? (
            <p className="text-sm text-gray-300">
              Strongest:{" "}
              <span className="font-medium text-white">
                {report.strongestMonth.monthLabel}
              </span>{" "}
              <span className="text-emerald-300">
                {formatPnlCurrency(report.strongestMonth.netPnl)}
              </span>
            </p>
          ) : null}
          {report.weakestMonth ? (
            <p className="text-sm text-gray-300">
              Weakest:{" "}
              <span className="font-medium text-white">
                {report.weakestMonth.monthLabel}
              </span>{" "}
              <span className="text-red-300">
                {formatPnlCurrency(report.weakestMonth.netPnl)}
              </span>
            </p>
          ) : null}
        </section>
      ) : null}

      <section className="space-y-3">
        <h3 className="text-sm font-semibold text-white">Month breakdown</h3>
        <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20">
          {report.monthRows.map((row) => {
            if (row.availability.kind === "upcoming") {
              return (
                <li
                  key={row.month}
                  className="flex items-center justify-between px-4 py-3 text-sm text-gray-500"
                >
                  <span>{row.monthLabel}</span>
                  <span className="text-xs">Upcoming</span>
                </li>
              )
            }
            const metrics = row.availability.metrics
            const canOpen = metrics.tradeCount > 0
            return (
              <li key={row.month}>
                <button
                  type="button"
                  disabled={!canOpen}
                  onClick={() => onOpenMonth(row.month)}
                  className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition hover:bg-white/5 disabled:cursor-default disabled:opacity-60"
                >
                  <span className="text-sm font-medium text-white">
                    {row.monthLabel}
                  </span>
                  <span className="text-right text-sm tabular-nums">
                    <span
                      className={
                        metrics.netPnl >= 0
                          ? "text-emerald-300"
                          : "text-red-300"
                      }
                    >
                      {formatPnlCurrency(metrics.netPnl)}
                    </span>
                    <span className="block text-xs text-gray-500">
                      {metrics.tradeCount} trades
                      {canOpen ? " · View report" : ""}
                    </span>
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      </section>

      <p className="text-xs text-gray-500">
        Performance reports are for journaling and education only — not investment
        advice.
      </p>
    </div>
  )
}

export default function YearlyTradingReportModal({
  open,
  onClose,
  trades,
  initialYear,
  onYearChange,
  viewerUserId,
  onViewTrade,
}: YearlyTradingReportModalProps) {
  const years = useMemo(
    () => availableTradingReportYears(trades),
    [trades]
  )
  const [selectedYear, setSelectedYear] = useState<number | null>(initialYear)
  const [monthReport, setMonthReport] = useState<TradingReport | null>(null)
  const [monthBestTrade, setMonthBestTrade] = useState<any | null>(null)

  useEffect(() => {
    if (open) setSelectedYear(initialYear)
  }, [open, initialYear])

  const activeYear =
    selectedYear ?? (initialYear != null ? initialYear : years.length === 1 ? years[0]! : null)

  const yearlyReport = useMemo(() => {
    if (activeYear == null) return null
    return generateYearlyTradingReport(trades, activeYear)
  }, [activeYear, trades])

  function pickYear(year: number) {
    setSelectedYear(year)
    onYearChange?.(year)
  }

  function openMonth(month: number) {
    if (activeYear == null) return
    const report = generateYearMonthTradingReport(
      { year: activeYear, month },
      trades
    )
    setMonthReport(report)
    const bestId = report.bestTradeId
    setMonthBestTrade(
      bestId ? trades.find((t) => String(t.id) === bestId) ?? null : null
    )
  }

  const showCatalog = activeYear == null

  return (
    <>
      <Modal
        open={open && !monthReport}
        onClose={onClose}
        size="lg"
        belowNavbar
        panelClassName="max-h-[min(90vh,calc(100dvh-5rem))] max-w-3xl overflow-y-auto"
        backdropClassName="bg-black/70 backdrop-blur-sm"
      >
        {showCatalog ? (
          <div className="space-y-6">
            <header className="space-y-2 border-b border-white/10 pb-4 pr-12">
              <p className="text-xs font-medium uppercase tracking-wider text-blue-300">
                Performance Reports
              </p>
              <h2 className="text-xl font-semibold text-white md:text-2xl">
                Yearly reports
              </h2>
              <p className="text-sm text-gray-400">
                Full-year performance with monthly breakdown and charts.
              </p>
            </header>
            {years.length === 0 ? (
              <p className="text-sm text-gray-400">
                Log trades to generate yearly performance reports.
              </p>
            ) : (
              <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20">
                {years.map((year) => (
                  <li key={year}>
                    <button
                      type="button"
                      onClick={() => pickYear(year)}
                      className="flex w-full items-center justify-between px-4 py-4 text-left transition hover:bg-white/5"
                    >
                      <span className="text-base font-semibold text-white">
                        {year}
                      </span>
                      <span className="text-sm text-blue-300">Open →</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ) : yearlyReport ? (
          <YearlyReportBody
            report={yearlyReport}
            onOpenMonth={openMonth}
            onBack={() => {
              setSelectedYear(null)
              onYearChange?.(null)
            }}
            showYearPicker={years.length > 1}
            years={years}
            year={activeYear!}
            onSelectYear={pickYear}
          />
        ) : null}
      </Modal>

      <TradingReportModal
        open={Boolean(monthReport)}
        onClose={() => {
          setMonthReport(null)
          setMonthBestTrade(null)
        }}
        report={monthReport}
        periodKey="monthly_this"
        onPeriodChange={() => {}}
        bestTrade={monthBestTrade}
        viewerUserId={viewerUserId}
        onViewTrade={onViewTrade}
        hidePeriodSelector
        bestTradeHeading="Best Trade This Month"
      />
    </>
  )
}
