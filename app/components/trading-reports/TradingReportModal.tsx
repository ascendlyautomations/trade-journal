"use client"

import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import Modal from "@/app/components/ui/Modal"
import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"
import { TRADING_REPORT_PERIOD_OPTIONS } from "@/lib/tradingReports/tradingReportPeriods"
import type { TradingReport, TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"

type TradingReportModalProps = {
  open: boolean
  onClose: () => void
  report: TradingReport | null
  periodKey: TradingReportPeriodKey
  onPeriodChange: (key: TradingReportPeriodKey) => void
  bestTrade: any | null
  viewerUserId?: string | null
  onViewTrade: (trade: { id?: string | null }) => void
}

function MetricCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 p-3">
      <p className="text-[11px] font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className="mt-1 text-sm font-semibold tabular-nums text-white md:text-base">
        {value}
      </p>
    </div>
  )
}

function formatMetricPnl(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPnlCurrency(value)
}

function formatProfitFactor(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return value.toFixed(2)
}

export default function TradingReportModal({
  open,
  onClose,
  report,
  periodKey,
  onPeriodChange,
  bestTrade,
  viewerUserId,
  onViewTrade,
}: TradingReportModalProps) {
  const metrics = report?.metrics

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      belowNavbar
      panelClassName="max-h-[min(90vh,calc(100dvh-5rem))] max-w-3xl overflow-y-auto"
      backdropClassName="bg-black/70 backdrop-blur-sm"
    >
      <div className="space-y-6">
        <header className="space-y-2 border-b border-white/10 pb-4">
          <p className="text-xs font-medium uppercase tracking-wider text-blue-300/90">
            Intelligence Report
          </p>
          <h2 className="text-xl font-semibold text-white md:text-2xl">
            {report?.title ?? "Trading Report"}
          </h2>
          {report?.dateRangeLabel ? (
            <p className="text-sm text-gray-400">{report.dateRangeLabel}</p>
          ) : null}

          <div className="flex flex-wrap gap-2 pt-2">
            {TRADING_REPORT_PERIOD_OPTIONS.map((option) => (
              <button
                key={option.key}
                type="button"
                onClick={() => onPeriodChange(option.key)}
                className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition md:text-sm ${
                  periodKey === option.key
                    ? "border-blue-400/60 bg-blue-500/20 text-white"
                    : "border-white/10 bg-white/5 text-gray-300 hover:bg-white/10"
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </header>

        {!report ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-gray-300">
            Loading report...
          </div>
        ) : (
          <>
            <section className={`${dashboardInsightCardClass} space-y-2`}>
              <h3 className="text-sm font-semibold text-gray-200">Summary</h3>
              <p className="text-sm leading-relaxed text-gray-300">
                {report.executiveSummary}
              </p>
            </section>

            {metrics ? (
              <section className="space-y-3">
                <h3 className="text-sm font-semibold text-gray-200">Key Metrics</h3>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
                  <MetricCell label="Net P&L" value={formatMetricPnl(metrics.netPnl)} />
                  <MetricCell
                    label="Win Rate"
                    value={
                      metrics.tradesTaken > 0
                        ? `${metrics.winRate.toFixed(1)}%`
                        : "—"
                    }
                  />
                  <MetricCell
                    label="Average RR"
                    value={
                      metrics.averageRr != null ? formatRR(metrics.averageRr) : "—"
                    }
                  />
                  <MetricCell
                    label="Profit Factor"
                    value={formatProfitFactor(metrics.profitFactor)}
                  />
                  <MetricCell
                    label="Trades Taken"
                    value={String(metrics.tradesTaken)}
                  />
                  <MetricCell
                    label="Best Day"
                    value={
                      metrics.bestDayLabel
                        ? `${metrics.bestDayLabel} (${formatMetricPnl(metrics.bestDayPnl)})`
                        : "—"
                    }
                  />
                  <MetricCell
                    label="Worst Day"
                    value={
                      metrics.worstDayLabel
                        ? `${metrics.worstDayLabel} (${formatMetricPnl(metrics.worstDayPnl)})`
                        : "—"
                    }
                  />
                  <MetricCell
                    label="Best Session"
                    value={metrics.bestSessionLabel ?? "—"}
                  />
                  <MetricCell
                    label="Worst Session"
                    value={metrics.worstSessionLabel ?? "—"}
                  />
                  <MetricCell
                    label="Most Traded Symbol"
                    value={metrics.mostTradedSymbol ?? "—"}
                  />
                  <MetricCell
                    label="Avg Hold Time"
                    value={
                      metrics.averageHoldTimeSeconds != null
                        ? formatHoldDurationSeconds(metrics.averageHoldTimeSeconds) ??
                          "—"
                        : "—"
                    }
                  />
                </div>
              </section>
            ) : null}

            {report.strengths.length > 0 ? (
              <section className="space-y-2">
                <h3 className="text-sm font-semibold text-emerald-300">✅ Strengths</h3>
                <ul className="space-y-2 text-sm text-gray-300">
                  {report.strengths.map((item) => (
                    <li
                      key={item}
                      className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-3 py-2"
                    >
                      {item}
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}

            {report.opportunities.length > 0 ? (
              <section className="space-y-2">
                <h3 className="text-sm font-semibold text-amber-300">⚠️ Opportunities</h3>
                <ul className="space-y-2 text-sm text-gray-300">
                  {report.opportunities.map((item) => (
                    <li
                      key={item}
                      className="rounded-lg border border-amber-500/20 bg-amber-500/5 px-3 py-2"
                    >
                      {item}
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}

            {report.recommendations.length > 0 ? (
              <section className="space-y-2">
                <h3 className="text-sm font-semibold text-blue-300">💡 Recommendations</h3>
                <ul className="space-y-2 text-sm text-gray-300">
                  {report.recommendations.map((item) => (
                    <li
                      key={item}
                      className="rounded-lg border border-blue-500/20 bg-blue-500/5 px-3 py-2"
                    >
                      {item}
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}

            {bestTrade ? (
              <section className="space-y-3">
                <h3 className="text-sm font-semibold text-white">
                  🏆 Best Trade This {report.kind === "weekly" ? "Week" : "Month"}
                </h3>
                <SharedTradeMessageCard
                  tradeId={bestTrade.id}
                  viewerUserId={viewerUserId}
                  initialTrade={bestTrade}
                  onViewTrade={onViewTrade}
                  showSocialLayer={false}
                />
              </section>
            ) : null}

            <section className={`${dashboardInsightCardClass} space-y-2`}>
              <h3 className="text-sm font-semibold text-gray-200">Key Takeaway</h3>
              <p className="text-sm leading-relaxed text-gray-300">{report.keyTakeaway}</p>
            </section>
          </>
        )}
      </div>
    </Modal>
  )
}
