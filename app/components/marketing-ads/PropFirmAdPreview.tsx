"use client"

import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightLabelClass,
  dashboardInsightMetricNegativeClass,
  dashboardInsightMetricPositiveClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import {
  buildPropfirmEquityCurveData,
  computePropfirmAccountMetrics,
  formatPropfirmUsd,
} from "@/lib/propfirmMetrics"
import { getDemoPropfirmAccounts, getDemoPropfirmTrades } from "@/lib/demo/demoPropfirm"
import {
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  CartesianGrid,
} from "recharts"
import InstagramAdShell from "./InstagramAdShell"

const RULE_CHIP_CLASS =
  "flex items-center gap-2.5 rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm"

function PropfirmStat({
  title,
  value,
  positive,
}: {
  title: string
  value: string
  positive?: boolean
}) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="flex min-h-[88px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-md">
      <p className="mb-1 text-sm text-gray-400">{title}</p>
      <span
        className={`block whitespace-nowrap text-xl font-semibold leading-tight tabular-nums ${color}`}
      >
        {value}
      </span>
    </div>
  )
}

export default function PropFirmAdPreview() {
  const accounts = getDemoPropfirmAccounts()
  const account = accounts.find((a) => a.mode === "eval") ?? accounts[0]
  const trades = getDemoPropfirmTrades([account.id])
  const metrics = computePropfirmAccountMetrics(trades, account)
  const equityCurve = buildPropfirmEquityCurveData(
    trades,
    metrics.startingBalance
  )

  const {
    displayCurrentBalance,
    cyclePnL,
    cycleProgress,
    cycleTrailingMetrics,
    cycleDailyMetrics,
    cycleConsistencyMetrics,
  } = metrics

  const progressPercent = cycleProgress.progressPercent
  const ddPercent = cycleProgress.ddPercent
  const maxDdLimit = Number(account.max_drawdown) || 0
  const drawdownUsed = cycleTrailingMetrics.maxDrawdownUsed
  const winningDays = cycleDailyMetrics.winningDays
  const winningDaysRequired =
    account.winning_days != null && Number(account.winning_days) > 0
  const winningDaysTargetMet =
    !winningDaysRequired || winningDays >= Number(account.winning_days)
  const consistencyRequired = cycleConsistencyMetrics.ruleActive

  return (
    <InstagramAdShell
      title="Stay Funded"
      subtitle="Track drawdown, profit targets, winning days, account rules, and payouts in one place."
      settleMs={1200}
    >
      <div className="space-y-4">
        <div className="flex items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/10 px-4 py-3 backdrop-blur-md">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
              Prop Firm Mode
            </p>
            <p className="mt-0.5 truncate text-lg font-semibold text-white">
              {account.name}
            </p>
          </div>
          <div
            className={`inline-flex shrink-0 items-center justify-center rounded-full border px-3 py-1.5 text-sm font-semibold ${
              cycleProgress.isPassed
                ? "border-green-500/30 bg-green-500/10 text-green-400"
                : "border-amber-500/30 bg-amber-500/10 text-amber-300"
            }`}
          >
            {cycleProgress.isPassed ? "PASSED" : "IN PROGRESS"}
          </div>
        </div>

        <div className="grid grid-cols-3 gap-3">
          <PropfirmStat
            title="Current Balance"
            value={formatPropfirmUsd(displayCurrentBalance)}
          />
          <PropfirmStat
            title="Current Cycle P&L"
            value={formatPropfirmUsd(cyclePnL)}
            positive={cyclePnL >= 0}
          />
          <PropfirmStat
            title="Cycle Winning Days"
            value={
              winningDaysRequired
                ? `${winningDays}/${Number(account.winning_days)}`
                : "—"
            }
          />
        </div>

        <div className="overflow-hidden rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
          <h2 className="mb-3 text-base font-semibold text-blue-300">
            Equity Curve
          </h2>
          <div className="h-[220px] w-full">
            <ResponsiveContainer width="100%" height={220}>
              <LineChart
                data={equityCurve}
                margin={{ top: 8, right: 16, left: 8, bottom: 8 }}
              >
                <CartesianGrid stroke="#334155" />
                <XAxis
                  dataKey="date"
                  stroke="#94a3b8"
                  tick={{ fill: "#94a3b8", fontSize: 11 }}
                  tickFormatter={(value) => {
                    const d = new Date(String(value))
                    if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                    return `${d.getMonth() + 1}/${d.getDate()}`
                  }}
                  interval="preserveStartEnd"
                  minTickGap={28}
                />
                <YAxis
                  stroke="#94a3b8"
                  tick={{ fill: "#94a3b8", fontSize: 11 }}
                  width={64}
                  tickFormatter={(value) =>
                    `$${Number(value).toLocaleString(undefined, {
                      maximumFractionDigits: 0,
                    })}`
                  }
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "#0f172a",
                    border: "1px solid rgba(255,255,255,0.1)",
                    borderRadius: "8px",
                  }}
                />
                <Line
                  type="monotone"
                  dataKey="balance"
                  stroke="#22c55e"
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className={dashboardInsightCardClass}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>Rule Status</h2>
            <div className="space-y-2">
              <div
                className={`${RULE_CHIP_CLASS} ${
                  cycleProgress.isPassed ? "text-green-400" : "text-amber-300"
                }`}
              >
                <span aria-hidden>{cycleProgress.isPassed ? "✓" : "○"}</span>
                <span className="font-medium">
                  {cycleProgress.isPassed
                    ? "Profit Target Met"
                    : "Profit Target Not Met Yet"}
                </span>
              </div>
              {winningDaysRequired ? (
                <div
                  className={`${RULE_CHIP_CLASS} ${
                    winningDaysTargetMet ? "text-green-400" : "text-amber-300"
                  }`}
                >
                  <span aria-hidden>{winningDaysTargetMet ? "✓" : "○"}</span>
                  <span className="font-medium">
                    {winningDaysTargetMet
                      ? "Minimum Trading Days Met"
                      : "Minimum Trading Days Not Met Yet"}
                  </span>
                </div>
              ) : null}
              {maxDdLimit > 0 ? (
                <div
                  className={`${RULE_CHIP_CLASS} ${
                    drawdownUsed > maxDdLimit ? "text-red-400" : "text-green-400"
                  }`}
                >
                  <span aria-hidden>
                    {drawdownUsed > maxDdLimit ? "✕" : "✓"}
                  </span>
                  <span className="font-medium">
                    {drawdownUsed > maxDdLimit
                      ? "Max Drawdown Violated"
                      : "Max Drawdown Within Limits"}
                  </span>
                </div>
              ) : null}
              {consistencyRequired ? (
                <div
                  className={`${RULE_CHIP_CLASS} ${
                    cycleConsistencyMetrics.isConsistent
                      ? "text-green-400"
                      : "text-amber-300"
                  }`}
                >
                  <span aria-hidden>
                    {cycleConsistencyMetrics.isConsistent ? "✓" : "○"}
                  </span>
                  <span className="font-medium">
                    {cycleConsistencyMetrics.isConsistent
                      ? "Consistency Rule Met"
                      : "Consistency Rule Not Met Yet"}
                  </span>
                </div>
              ) : null}
            </div>
          </div>

          <div className={dashboardInsightCardClass}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>
              Progress{" "}
              <span className="text-xs font-normal text-gray-500">
                (current cycle)
              </span>
            </h2>
            <div className={`space-y-2.5 ${dashboardInsightBodyClass}`}>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Cycle P&L</span>
                <span
                  className={
                    cyclePnL >= 0
                      ? dashboardInsightMetricPositiveClass
                      : dashboardInsightMetricNegativeClass
                  }
                >
                  {formatPropfirmUsd(cyclePnL)}
                </span>
              </div>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Profit Target</span>
                <span className="font-medium text-gray-200">
                  ${account.profit_target}
                </span>
              </div>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>
                  Max Drawdown Used
                </span>
                <span className="font-medium text-gray-200">
                  {formatPropfirmUsd(drawdownUsed)}
                </span>
              </div>
            </div>
            <div className="mt-4 space-y-3">
              <div>
                <div className="mb-1.5 flex justify-between text-sm text-gray-400">
                  <span>Profit target (cycle)</span>
                  <span className="tabular-nums">
                    {progressPercent.toFixed(0)}%
                  </span>
                </div>
                <div className="h-2.5 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500"
                    style={{ width: `${Math.min(100, progressPercent)}%` }}
                  />
                </div>
              </div>
              <div>
                <div className="mb-1.5 flex justify-between text-sm text-gray-400">
                  <span>Drawdown used</span>
                  <span className="tabular-nums">{ddPercent.toFixed(0)}%</span>
                </div>
                <div className="h-2.5 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-amber-400 to-red-500"
                    style={{ width: `${Math.min(100, ddPercent)}%` }}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </InstagramAdShell>
  )
}
