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
  formatPropfirmUsd,
  type ConsistencyRuleResult,
  type PropfirmAccountRules,
  type PropfirmTrade,
  type TrailingDrawdownResult,
} from "@/lib/propfirmMetrics"
import LockedFeature from "@/app/components/LockedFeature"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonAnalyticsPage } from "@/app/components/ui/skeletons"
import { isProActive } from "@/lib/subscription"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  MANAGE_ACCOUNTS_VALUE,
  navigateToManageAccounts,
} from "@/app/components/TradeFilterBar"

const SECTION_PANEL =
  "rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-3"

const SELECT_CLASS =
  "h-[34px] w-full rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"

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
    <div className="flex min-h-[72px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-2.5 text-center backdrop-blur-md md:p-3">
      <p className="mb-1 text-xs md:text-sm text-gray-400">{title}</p>
      <span
        className={`block font-semibold text-base leading-tight whitespace-nowrap tabular-nums md:text-lg lg:text-xl ${color}`}
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
    <div className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10">
      <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-[1600px] flex-col gap-3 px-1 md:gap-4 md:px-6">
        {children}
      </div>
    </div>
  )
}

function PropfirmEquityCurve({
  data,
  startingBalance,
}: {
  data: EquityCurvePoint[]
  startingBalance: number
}) {
  const yAxisDomain = (() => {
    if (startingBalance <= 0) return undefined

    const lowerBound = startingBalance * 0.92
    const defaultUpperBound = startingBalance * 1.3
    const highestBalance = data.reduce(
      (highest, point) => Math.max(highest, point.balance),
      startingBalance
    )
    const upperBoundStep = 5000
    const dynamicUpperBound =
      highestBalance > defaultUpperBound
        ? Math.ceil((highestBalance + 5000) / upperBoundStep) * upperBoundStep
        : defaultUpperBound

    return [lowerBound, dynamicUpperBound]
  })()

  return (
    <div className={SECTION_PANEL}>
      <div className="mb-1.5 flex flex-col gap-0.5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="mb-1 text-sm font-semibold text-blue-300">Equity Curve</h2>
          <p className="text-xs text-gray-400">
            Account balance progression by trading day
          </p>
        </div>
      </div>

      {data.length > 1 ? (
        <div className="h-[220px] w-full overflow-hidden sm:h-[280px]">
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
          className="py-6"
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
  let sizePart =
    acc.account_size != null && acc.account_size !== ""
      ? String(acc.account_size).trim()
      : ""
  if (sizePart && !/k/i.test(sizePart)) {
    const n = Number(sizePart.replace(/,/g, ""))
    if (Number.isFinite(n) && n >= 1 && n <= 999) {
      sizePart = `${n}K`
    }
  }
  return `${acc.name} • ${sizePart || "—"} • ${acc.mode}`
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
  const emptyAccountLabel = "— • — • —"

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
        <div className={SECTION_PANEL}>
          <div className="flex flex-col gap-2 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
                Analytics
              </p>
              <h1 className="mt-0.5 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
                Prop Firm Mode
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Track rule progress, drawdown room, and account balance from one
                stabilized view.
              </p>
            </div>

            <div
              className={`inline-flex w-fit rounded-full border px-3 py-1 text-sm font-semibold ${
                isEmptyAccounts
                  ? "border-white/15 bg-white/5 text-gray-400"
                  : status === "PASSED"
                    ? "border-green-500/30 bg-green-500/10 text-green-400"
                    : status === "FAILED"
                      ? "border-red-500/30 bg-red-500/10 text-red-400"
                      : "border-yellow-500/30 bg-yellow-500/10 text-yellow-400"
              }`}
            >
              {isEmptyAccounts ? "—" : statusLabel}
            </div>
          </div>

          <div className="mt-2 grid gap-2 md:grid-cols-[minmax(0,420px)_1fr] md:items-center">
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
                  {acc.name} •{" "}
                  {acc.account_size == null ? "" : String(acc.account_size)} •{" "}
                  {acc.mode}
                </option>
              ))}
              <option disabled>────────────────────</option>
              <option value={MANAGE_ACCOUNTS_VALUE}>⚙️ Manage Accounts</option>
            </select>

            <p className="text-sm text-gray-400 md:text-right">
              Selected:{" "}
              <span className="font-medium text-gray-200">
                {isEmptyAccounts ? emptyAccountLabel : selectedAccountLabel}
              </span>
            </p>
          </div>
        </div>

        {isEmptyAccounts ? (
          <div className="flex justify-center">
            <Link
              href="/settings#trading-accounts"
              className="text-sm font-medium text-blue-300 hover:text-blue-200"
            >
              Create Prop Firm Account →
            </Link>
          </div>
        ) : null}

        {loadingTrades ? (
          <SkeletonAnalyticsPage />
        ) : (
          <>
        {selectedAccount && (
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
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
                winningDaysTargetMet ? "text-green-400" : "text-yellow-400"
              }
            />
          </div>
        )}

        {selectedAccount && (
          <PropfirmEquityCurve
            data={equityCurveData}
            startingBalance={startingBalance}
          />
        )}

        {selectedAccount && (
          <div className={SECTION_PANEL}>
            <div className="mb-1.5 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-blue-300">Rule Status</h2>
              <span className="text-xs uppercase tracking-wide text-gray-500">
                Evaluation
              </span>
            </div>

            <div className="grid gap-1.5 text-sm sm:grid-cols-2">
              <div
                className={`flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 ${
                  maxDdLimit > 0 && trailingMetrics.breachedTrailingDD
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span>
                  {maxDdLimit > 0 && trailingMetrics.breachedTrailingDD ? "❌" : "✔"}
                </span>
                <span className="font-medium">Max Drawdown</span>
              </div>

              <div
                className={`flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 ${
                  dailyDrawdownBreached
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span>{dailyDrawdownBreached ? "❌" : "✔"}</span>
                <span className="font-medium">Daily Drawdown</span>
              </div>

              <div
                className={`flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 ${
                  winningDaysTargetMet
                    ? "text-green-400"
                    : "text-yellow-400"
                }`}
              >
                <span>{winningDaysTargetMet ? "✔" : "⚠"}</span>
                <span className="font-medium">Winning Days</span>
              </div>

              <div
                className={`flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 ${
                  !consistencyMetrics.ruleActive
                    ? "text-gray-400"
                    : consistencyMetrics.isConsistent
                      ? "text-green-400"
                      : "text-red-400"
                }`}
              >
                <span>
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
            <h2 className="mb-1.5 text-sm font-semibold text-blue-300">
              Account Rules
            </h2>

            <div className="grid gap-x-6 gap-y-1 text-sm text-gray-300 sm:grid-cols-2">
              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Account size</span>
                <span className="font-medium text-gray-100">
                  {startingBalance > 0 ? formatPropfirmUsd(startingBalance) : "—"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Consistency</span>
                <span className="font-medium text-gray-100">
                  {selectedAccount.consistency || 0}%
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Max Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.max_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Daily Drawdown</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.daily_drawdown}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Profit Target</span>
                <span className="font-medium text-gray-100">
                  ${selectedAccount.profit_target}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Winning Days</span>
                <span className="font-medium text-gray-100">
                  {selectedAccount.winning_days}
                </span>
              </div>
            </div>
          </div>
        )}

        {selectedAccount && (
          <div className={SECTION_PANEL}>
            <h2 className="mb-1.5 text-sm font-semibold text-blue-300">
              Progress
            </h2>

            <div className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Total P&L</span>
                <span className={totalPnL >= 0 ? "text-green-400" : "text-red-400"}>
                  {formatPropfirmUsd(totalPnL)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Profit Target</span>
                <span className="text-gray-200">${selectedAccount.profit_target}</span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Max Drawdown Used</span>
                <span
                  className={
                    maxDdLimit > 0 && drawdownUsed > maxDdLimit
                      ? "text-red-400"
                      : "text-gray-200"
                  }
                >
                  {formatPropfirmUsd(drawdownUsed)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Drawdown Floor</span>
                <span className="text-gray-200">
                  {formatPropfirmUsd(trailingMetrics.drawdownFloor)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Today P&L</span>
                <span className={todayPnL >= 0 ? "text-green-400" : "text-red-400"}>
                  {formatPropfirmUsd(todayPnL)}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Biggest Trade</span>
                <span>{formatPropfirmUsd(consistencyMetrics.biggestWin)}</span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Allowed Max</span>
                <span>
                  {consistencyMetrics.ruleActive
                    ? formatPropfirmUsd(consistencyMetrics.allowedMax)
                    : "—"}
                </span>
              </div>

              <div className="flex justify-between gap-3">
                <span className="text-gray-400">Consistency</span>
                <span
                  className={
                    !consistencyMetrics.ruleActive
                      ? "text-gray-400"
                      : consistencyMetrics.isConsistent
                        ? "text-green-400"
                        : "text-red-400"
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

            <div className="mt-2 space-y-1.5">
              <div>
                <div className="mb-1 flex justify-between text-xs text-gray-400">
                  <span>Profit target</span>
                  <span>{progressPercent.toFixed(0)}%</span>
                </div>
                <div className="h-1.5 w-full rounded bg-white/10">
                  <div
                    className="h-1.5 rounded bg-green-500"
                    style={{ width: `${progressPercent}%` }}
                  />
                </div>
              </div>

              <div>
                <div className="mb-1 flex justify-between text-xs text-gray-400">
                  <span>Drawdown used</span>
                  <span>{ddPercent.toFixed(0)}%</span>
                </div>
                <div className="h-1.5 w-full rounded bg-white/10">
                  <div
                    className="h-1.5 rounded bg-red-500"
                    style={{ width: `${ddPercent}%` }}
                  />
                </div>
              </div>
            </div>

            {selectedAccount &&
              maxDdLimit > 0 &&
              trailingMetrics.breachedTrailingDD && (
                <div className="mt-3 text-sm text-red-400">
                  ⚠️ Trailing max drawdown breached (balance below drawdown floor)
                </div>
              )}

            {selectedAccount &&
              dailyDrawdownBreached && (
                <div className="mt-1.5 text-sm text-red-400">
                  ⚠️ Daily drawdown exceeded
                </div>
              )}
          </div>
        )}

        <div className={SECTION_PANEL}>
          <div className="mb-1.5 flex items-center justify-between gap-2">
            <div>
              <h2 className="text-sm font-semibold text-blue-300">
                Daily Performance
              </h2>
              <p className="text-xs text-gray-400">
                Aggregated by trading day
              </p>
            </div>
            <span className="rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-xs text-gray-300">
              {dailyRows.length} days
            </span>
          </div>

          <div className="max-h-56 space-y-1 overflow-y-auto pr-1 text-sm">
            {dailyRows.length > 0 ? (
              dailyRows.map(([date, pnl]) => (
                <div
                  key={date}
                  className="flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5"
                >
                  <span className="font-medium text-gray-300">{date}</span>
                  <span
                    className={
                      pnl >= 0
                        ? "font-semibold text-green-400"
                        : "font-semibold text-red-400"
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
              <div className="rounded-lg border border-dashed border-white/10 bg-white/5 px-3 py-4 text-center text-sm text-gray-400">
                No daily performance yet.
              </div>
            )}
          </div>
        </div>

        {!selectedAccount && !isEmptyAccounts ? (
          <p className="text-center text-sm text-gray-400">
            Select a prop firm account to view progress
          </p>
        ) : null}
          </>
        )}
    </PropfirmPageShell>
  )
}
