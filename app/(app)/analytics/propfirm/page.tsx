"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useMemo, useState, type ReactNode } from "react"
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import { supabase } from "@/lib/supabaseClient"
import {
  computePropfirmAccountMetrics,
  computePropfirmEquityCurveYDomain,
  formatPropfirmUsd,
  type ConsistencyRuleResult,
  type PropfirmAccountRules,
  type PropfirmTrade,
  type TrailingDrawdownResult,
} from "@/lib/propfirmMetrics"
import LockedFeature from "@/app/components/LockedFeature"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonAnalyticsPage } from "@/app/components/ui/skeletons"
import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightLabelClass,
  dashboardInsightMetricNegativeClass,
  dashboardInsightMetricPositiveClass,
  dashboardInsightTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
import { isProActive } from "@/lib/subscription"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  MANAGE_ACCOUNTS_VALUE,
  navigateToManageAccounts,
} from "@/app/components/TradeFilterBar"
import { formatAccountNameWithSizeDisplay } from "@/lib/tradeAccountDisplay"

const SECTION_PANEL = dashboardInsightCardClass

const SELECT_CLASS =
  "h-9 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-1.5 text-sm text-white transition-colors hover:bg-white/5 focus:border-blue-400/50 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

const INNER_ROW_CLASS =
  "flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 transition-colors hover:bg-white/[0.07]"

const RULE_CHIP_CLASS =
  "flex items-center gap-2.5 rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm transition-colors hover:bg-white/[0.07]"

function PropfirmStat({
  title,
  value,
  positive,
  valueClassName,
}: {
  title: string
  value: string
  positive?: boolean
  valueClassName?: string
}) {
  let color = valueClassName ?? "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="flex min-h-[90px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-3 text-center backdrop-blur-md md:p-4">
      <p className="mb-1 text-xs text-gray-400 md:text-sm">{title}</p>
      <span
        className={`block whitespace-nowrap text-base font-semibold leading-tight tabular-nums md:text-lg lg:text-xl ${color}`}
      >
        {value}
      </span>
    </div>
  )
}

const PROPFIRM_ACCOUNT_FIELDS =
  "id,name,account_size,mode,consistency,max_drawdown,daily_drawdown,profit_target,winning_days"

const PROPFIRM_TRADE_FIELDS = "id,pnl,date,trade_date,entry_time,created_at"

type PropfirmAccount = PropfirmAccountRules & {
  id: string | number
  name?: string | null
  mode?: string | null
  daily_drawdown?: number | string | null
  winning_days?: number | string | null
}

type EquityCurvePoint = {
  date: string
  balance: number
  pnl: number
}

function PropfirmPageShell({ children }: { children: ReactNode }) {
  return (
    <div className="w-full px-3 pb-3 pt-0 text-white md:px-4 md:pb-10">
      <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-[1600px] flex-col gap-6 px-1 md:gap-8 md:px-6">
        {children}
      </div>
    </div>
  )
}

function PropfirmEquityCurve({
  data,
  referenceYValues = [],
}: {
  data: EquityCurvePoint[]
  referenceYValues?: number[]
}) {
  const values = data.map((point) => point.balance)
  const yAxisDomain = computePropfirmEquityCurveYDomain(values, {
    includeValues: referenceYValues,
  })

  return (
    <div className={SECTION_PANEL}>
      <div className="mb-3 flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-sm font-semibold text-blue-300 md:text-base">
            Equity Curve
          </h2>
          <p className="mt-0.5 text-xs text-gray-400 md:text-sm">
            Account balance progression by trading day
          </p>
        </div>
      </div>

      {data.length > 1 ? (
        <div className="h-[240px] w-full overflow-hidden sm:h-[280px] md:h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={data}
              margin={{ top: 4, right: 12, left: 8, bottom: 10 }}
            >
              <CartesianGrid stroke="#334155" strokeDasharray="3 3" />
              <XAxis
                dataKey="date"
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 11 }}
                tickFormatter={(value) => {
                  const label = String(value)
                  if (label === "Start") return label
                  const d = new Date(`${label}T12:00:00Z`)
                  if (Number.isNaN(d.getTime())) return label
                  return `${d.getUTCMonth() + 1}/${d.getUTCDate()}`
                }}
                interval="preserveStartEnd"
                minTickGap={20}
              />
              <YAxis
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 11 }}
                tickFormatter={(value) => formatPropfirmUsd(Number(value))}
                width={72}
                domain={yAxisDomain}
                allowDataOverflow
              />
              <Tooltip
                formatter={(value, name) => {
                  if (name === "Balance") {
                    return [formatPropfirmUsd(Number(value)), "Balance"]
                  }
                  return [formatPropfirmUsd(Number(value)), "Day P&L"]
                }}
                labelFormatter={(label) => `Day: ${String(label)}`}
                contentStyle={{
                  backgroundColor: "#0f172a",
                  border: "1px solid rgba(255,255,255,0.12)",
                  borderRadius: "10px",
                }}
                labelStyle={{ color: "#94a3b8" }}
              />
              <Line
                type="monotone"
                dataKey="balance"
                name="Balance"
                stroke="#22c55e"
                strokeWidth={2.5}
                dot={data.length <= 12 ? { r: 3, fill: "#22c55e" } : false}
                activeDot={{ r: 5 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="border-0 bg-transparent py-8"
        />
      )}
    </div>
  )
}

export type { ConsistencyRuleResult, TrailingDrawdownResult }

export {
  computeConsistencyRule,
  computeTrailingDrawdown,
} from "@/lib/propfirmMetrics"

function formatPropfirmAccountLabel(acc: PropfirmAccount | null) {
  if (!acc) return "None"
  const nameSize = formatAccountNameWithSizeDisplay(
    acc.name,
    acc.account_size
  )
  return `${nameSize || acc.name} • ${acc.mode}`
}

export default function PropFirmPage() {
  const router = useRouter()
  const [planChecked, setPlanChecked] = useState(false)
  const [hasProAccess, setHasProAccess] = useState(false)
  const [accounts, setAccounts] = useState<PropfirmAccount[]>([])
  const [accountsLoaded, setAccountsLoaded] = useState(false)
  const [selectedAccount, setSelectedAccount] =
    useState<PropfirmAccount | null>(null)
  const [trades, setTrades] = useState<PropfirmTrade[]>([])
  const [loadingTrades, setLoadingTrades] = useState(false)

  const accountMetrics = useMemo(
    () => computePropfirmAccountMetrics(trades, selectedAccount),
    [trades, selectedAccount]
  )

  const {
    dailyMetrics,
    startingBalance,
    trailingMetrics,
    consistencyMetrics,
    totalPnL,
    progress,
  } = accountMetrics
  const { dailyRows, winningDays, todayPnL, worstDailyLossUsed } = dailyMetrics
  const selectedAccountLabel = useMemo(
    () => formatPropfirmAccountLabel(selectedAccount),
    [selectedAccount]
  )
  const equityCurveData = useMemo(() => {
    if (!selectedAccount || startingBalance <= 0) return []

    let balance = startingBalance
    const points: EquityCurvePoint[] = [
      { date: "Start", balance, pnl: 0 },
    ]

    for (const [date, pnl] of dailyRows) {
      balance += pnl
      points.push({ date, balance, pnl })
    }

    return points
  }, [dailyRows, selectedAccount, startingBalance])

  const equityCurveReferenceY = useMemo(() => {
    if (!selectedAccount || startingBalance <= 0) return []

    const profitTarget = Number(selectedAccount.profit_target) || 0
    const refs: number[] = []

    if (profitTarget > 0) {
      refs.push(startingBalance + profitTarget)
    }
    if (Number.isFinite(trailingMetrics.drawdownFloor)) {
      refs.push(trailingMetrics.drawdownFloor)
    }

    return refs
  }, [selectedAccount, startingBalance, trailingMetrics.drawdownFloor])

  useEffect(() => {
    async function checkPlan() {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user?.id) {
        setHasProAccess(false)
        setPlanChecked(true)
        return
      }
      const { data: profile } = await supabase
        .from("profiles")
        .select("is_pro, subscription_status")
        .eq("id", user.id)
        .maybeSingle()
      setHasProAccess(isProActive(profile))
      setPlanChecked(true)
    }
    void checkPlan()
  }, [])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return
    async function loadAccounts() {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        setAccountsLoaded(true)
        return
      }

      const { data, error } = await supabase
        .from("accounts")
        .select(PROPFIRM_ACCOUNT_FIELDS)
        .eq("user_id", user.id)
        .eq("category", "Prop Firm")

      if (error) {
        console.error(error)
        setAccountsLoaded(true)
        return
      }

      setAccounts(data || [])
      setAccountsLoaded(true)
    }

    loadAccounts()
  }, [planChecked, hasProAccess])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return
    if (!selectedAccount) return

    const selectedAccountId = selectedAccount.id
    setTrades([])

    async function loadTrades() {
      setLoadingTrades(true)
      try {
        const { data, error } = await supabase
          .from("trades")
          .select(PROPFIRM_TRADE_FIELDS)
          .eq("account_id", selectedAccountId)
          .order("trade_date", { ascending: true })
          .order("entry_time", { ascending: true })

        if (error) {
          console.error(error)
          return
        }

        setTrades(data || [])
      } finally {
        setLoadingTrades(false)
      }
    }

    loadTrades()
  }, [selectedAccount, planChecked, hasProAccess])

  if (!planChecked) {
    return (
      <PropfirmPageShell>
        <SkeletonAnalyticsPage />
      </PropfirmPageShell>
    )
  }

  if (!hasProAccess) {
    return (
      <PropfirmPageShell>
        <LockedFeature title="Prop Firm Mode" className="mx-auto max-w-lg" />
      </PropfirmPageShell>
    )
  }

  const isEmptyAccounts = accountsLoaded && accounts.length === 0

  const drawdownUsed = trailingMetrics.maxDrawdownUsed
  const { progressPercent, status, ddPercent, distanceDanger } = progress
  const statusLabel = status === "IN PROGRESS" ? "ACTIVE" : status
  const distanceToDD = trailingMetrics.distanceToDD
  const maxDdLimit = Number(selectedAccount?.max_drawdown) || 0
  const dailyDrawdownBreached =
    worstDailyLossUsed > Number(selectedAccount?.daily_drawdown)
  const winningDaysTargetMet =
    winningDays >= Number(selectedAccount?.winning_days)
  const distanceClassName =
    maxDdLimit <= 0
      ? "text-gray-400"
      : distanceToDD < 0 || distanceDanger
        ? "text-red-400"
        : "text-green-400"

  return (
    <PropfirmPageShell>
        <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
              Analytics
            </p>
            <h1 className="mt-0.5 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
              Prop Firm Mode
            </h1>
            <p className="mt-1 max-w-2xl text-sm text-gray-400 md:text-base">
              Track rule progress, drawdown room, and account balance from one
              stabilized view.
            </p>
          </div>

          {selectedAccount ? (
            <div
              className={`inline-flex w-fit shrink-0 rounded-full border px-3.5 py-1.5 text-sm font-semibold ${
                status === "PASSED"
                  ? "border-green-500/30 bg-green-500/10 text-green-400"
                  : status === "FAILED"
                    ? "border-red-500/30 bg-red-500/10 text-red-400"
                    : "border-amber-500/30 bg-amber-500/10 text-amber-300"
              }`}
            >
              {statusLabel}
            </div>
          ) : null}
        </div>

        <div className={SECTION_PANEL}>
          <div className="grid gap-3 md:grid-cols-[minmax(0,420px)_1fr] md:items-center">
            <select
              value={
                selectedAccount?.id != null ? String(selectedAccount.id) : ""
              }
              onChange={(e) => {
                const value = e.target.value
                if (value === MANAGE_ACCOUNTS_VALUE) {
                  navigateToManageAccounts(router)
                  return
                }
                const selected = accounts.find(
                  (a) => String(a.id) === value
                )
                setSelectedAccount(selected ?? null)
              }}
              className={SELECT_CLASS}
            >
              <option value="">Select Account</option>
              {accounts.map((acc) => (
                <option key={acc.id} value={String(acc.id)}>
                  {formatAccountNameWithSizeDisplay(acc.name, acc.account_size)} •{" "}
                  {acc.mode}
                </option>
              ))}
              <option disabled>────────────────────</option>
              <option value={MANAGE_ACCOUNTS_VALUE}>⚙️ Manage Accounts</option>
            </select>

            <p className="text-sm text-gray-400 md:text-right">
              Selected:{" "}
              <span className="font-medium text-gray-200">
                {selectedAccountLabel}
              </span>
            </p>
          </div>
        </div>

        {loadingTrades ? (
          <SkeletonAnalyticsPage />
        ) : (
          <>
        {selectedAccount && (
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <PropfirmStat
              title="Total P&L"
              value={formatPropfirmUsd(totalPnL)}
              positive={totalPnL >= 0}
            />
            <PropfirmStat
              title="Current Balance"
              value={formatPropfirmUsd(trailingMetrics.currentBalance)}
            />
            <PropfirmStat
              title="Distance to DD"
              value={formatPropfirmUsd(distanceToDD)}
              valueClassName={distanceClassName}
            />
            <PropfirmStat
              title="Winning Days"
              value={`${winningDays}/${Number(selectedAccount.winning_days) || 0}`}
              valueClassName={
                winningDaysTargetMet ? "text-green-400" : "text-amber-300"
              }
            />
          </div>
        )}

        {selectedAccount && (
          <PropfirmEquityCurve
            data={equityCurveData}
            referenceYValues={equityCurveReferenceY}
          />
        )}

        {selectedAccount && (
          <div className={SECTION_PANEL}>
            <div className="mb-3 flex items-center justify-between gap-2">
              <h2 className={dashboardInsightTitleClass}>Rule Status</h2>
              <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 text-xs font-medium uppercase tracking-wide text-gray-400">
                Evaluation
              </span>
            </div>

            <div className="grid gap-2 sm:grid-cols-2">
              <div
                className={`${RULE_CHIP_CLASS} ${
                  maxDdLimit > 0 && trailingMetrics.breachedTrailingDD
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span aria-hidden>
                  {maxDdLimit > 0 && trailingMetrics.breachedTrailingDD ? "❌" : "✔"}
                </span>
                <span className="font-medium">Max Drawdown</span>
              </div>

              <div
                className={`${RULE_CHIP_CLASS} ${
                  dailyDrawdownBreached
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span aria-hidden>{dailyDrawdownBreached ? "❌" : "✔"}</span>
                <span className="font-medium">Daily Drawdown</span>
              </div>

              <div
                className={`${RULE_CHIP_CLASS} ${
                  winningDaysTargetMet
                    ? "text-green-400"
                    : "text-amber-300"
                }`}
              >
                <span aria-hidden>{winningDaysTargetMet ? "✔" : "⚠"}</span>
                <span className="font-medium">Winning Days</span>
              </div>

              <div
                className={`${RULE_CHIP_CLASS} ${
                  !consistencyMetrics.ruleActive
                    ? "text-gray-400"
                    : consistencyMetrics.isConsistent
                      ? "text-green-400"
                      : "text-red-400"
                }`}
              >
                <span aria-hidden>
                  {!consistencyMetrics.ruleActive
                    ? "—"
                    : consistencyMetrics.isConsistent
                      ? "✔"
                      : "✖"}
                </span>
                <span className="font-medium">Consistency</span>
              </div>
            </div>
          </div>
        )}

        {selectedAccount && (
          <div className={SECTION_PANEL}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>
              Account Rules
            </h2>

            <div className={`grid gap-x-6 gap-y-2.5 sm:grid-cols-2 ${dashboardInsightBodyClass}`}>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Account size</span>
                <span className="font-medium text-gray-100">
                  {startingBalance > 0 ? formatPropfirmUsd(startingBalance) : "—"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Consistency</span>
                <span className="font-medium text-gray-100">
                  {selectedAccount.consistency || 0}%
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Max Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.max_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Daily Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.daily_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Profit Target</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.profit_target}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Winning Days</span>
                <span className="font-medium text-gray-100">
                  {selectedAccount.winning_days}
                </span>
              </div>
            </div>
          </div>
        )}

        {selectedAccount && (
          <div className={SECTION_PANEL}>
            <h2 className={`${dashboardInsightTitleClass} mb-3`}>Progress</h2>

            <div className={`grid gap-x-6 gap-y-2.5 sm:grid-cols-2 ${dashboardInsightBodyClass}`}>
              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Total P&L</span>
                <span className={totalPnL >= 0 ? dashboardInsightMetricPositiveClass : dashboardInsightMetricNegativeClass}>
                  {formatPropfirmUsd(totalPnL)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Profit Target</span>
                <span className="font-medium text-gray-200">${selectedAccount.profit_target}</span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Max Drawdown Used</span>
                <span
                  className={
                    maxDdLimit > 0 && drawdownUsed > maxDdLimit
                      ? dashboardInsightMetricNegativeClass
                      : "font-medium text-gray-200"
                  }
                >
                  {formatPropfirmUsd(drawdownUsed)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Drawdown Floor</span>
                <span className="font-medium text-gray-200">
                  {formatPropfirmUsd(trailingMetrics.drawdownFloor)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Today P&L</span>
                <span className={todayPnL >= 0 ? dashboardInsightMetricPositiveClass : dashboardInsightMetricNegativeClass}>
                  {formatPropfirmUsd(todayPnL)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Biggest Trade</span>
                <span className="font-medium text-gray-200">{formatPropfirmUsd(consistencyMetrics.biggestWin)}</span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Allowed Max</span>
                <span className="font-medium text-gray-200">
                  {consistencyMetrics.ruleActive
                    ? formatPropfirmUsd(consistencyMetrics.allowedMax)
                    : "—"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className={dashboardInsightLabelClass}>Consistency</span>
                <span
                  className={
                    !consistencyMetrics.ruleActive
                      ? "text-gray-400"
                      : consistencyMetrics.isConsistent
                        ? dashboardInsightMetricPositiveClass
                        : dashboardInsightMetricNegativeClass
                  }
                >
                  {!consistencyMetrics.ruleActive
                    ? "Set rule % to track"
                    : consistencyMetrics.isConsistent
                      ? "Consistent"
                      : "Not Consistent"}
                </span>
              </div>
            </div>

            <div className="mt-4 space-y-3">
              <div>
                <div className="mb-1.5 flex justify-between text-xs text-gray-400 md:text-sm">
                  <span>Profit target</span>
                  <span className="tabular-nums">{progressPercent.toFixed(0)}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 transition-[width] duration-300"
                    style={{ width: `${progressPercent}%` }}
                  />
                </div>
              </div>

              <div>
                <div className="mb-1.5 flex justify-between text-xs text-gray-400 md:text-sm">
                  <span>Drawdown used</span>
                  <span className="tabular-nums">{ddPercent.toFixed(0)}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-red-500 transition-[width] duration-300"
                    style={{ width: `${ddPercent}%` }}
                  />
                </div>
              </div>
            </div>

            {selectedAccount &&
              maxDdLimit > 0 &&
              trailingMetrics.breachedTrailingDD && (
                <div className="mt-4 rounded-lg border border-red-500/20 bg-red-500/10 px-3 py-2.5 text-sm text-red-400">
                  Trailing max drawdown breached (balance below drawdown floor)
                </div>
              )}

            {selectedAccount &&
              dailyDrawdownBreached && (
                <div className="mt-2 rounded-lg border border-red-500/20 bg-red-500/10 px-3 py-2.5 text-sm text-red-400">
                  Daily drawdown exceeded
                </div>
              )}
          </div>
        )}

        <div className={SECTION_PANEL}>
          <div className="mb-3 flex items-center justify-between gap-2">
            <div>
              <h2 className={dashboardInsightTitleClass}>Daily Performance</h2>
              <p className="mt-0.5 text-xs text-gray-400 md:text-sm">
                Aggregated by trading day
              </p>
            </div>
            <span className="shrink-0 rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 text-xs font-medium tabular-nums text-gray-300">
              {dailyRows.length} days
            </span>
          </div>

          <div className="max-h-64 space-y-1.5 overflow-y-auto pr-1 text-sm">
            {dailyRows.length > 0 ? (
              dailyRows.map(([date, pnl]) => (
                <div
                  key={date}
                  className={INNER_ROW_CLASS}
                >
                  <span className="font-medium text-gray-300">{date}</span>
                  <span
                    className={
                      pnl >= 0
                        ? dashboardInsightMetricPositiveClass
                        : dashboardInsightMetricNegativeClass
                    }
                  >
                    {formatPnlCurrency(pnl, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 2,
                    })}
                  </span>
                </div>
              ))
            ) : (
              <div className="rounded-lg border border-dashed border-white/10 bg-white/5 px-4 py-6 text-center text-sm text-gray-400">
                No daily performance yet.
              </div>
            )}
          </div>
        </div>

        {isEmptyAccounts ? (
          <EmptyState
            title="No Prop Firm Accounts"
            description="You don't have any Prop Firm accounts yet. Create one in Settings to start tracking rule progress."
            action={
              <Link
                href="/settings#trading-accounts"
                className="inline-flex items-center justify-center rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
              >
                Create Prop Firm Account
              </Link>
            }
          />
        ) : !selectedAccount ? (
          <EmptyState
            title="Select an Account"
            description="Choose a prop firm account above to view drawdown room, rule status, and daily performance."
            className="py-8"
          />
        ) : null}
          </>
        )}
    </PropfirmPageShell>
  )
}
