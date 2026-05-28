"use client"

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
import { isProActive } from "@/lib/subscription"

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
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
      <div className="w-full px-2 pb-4 pt-3 text-white md:px-4 md:pb-6 md:pt-4">{children}</div>
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
    <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-3 shadow-lg shadow-black/10">
      <div className="mb-2 flex flex-col gap-0.5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-base font-semibold text-white">Equity Curve</h2>
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
        <div className="flex min-h-[140px] items-center justify-center rounded-lg border border-dashed border-white/10 bg-white/[0.03] text-center text-sm text-gray-400">
          Add trades to this prop firm account to build an equity curve.
        </div>
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
  const [planChecked, setPlanChecked] = useState(false)
  const [hasProAccess, setHasProAccess] = useState(false)
  const [accounts, setAccounts] = useState<PropfirmAccount[]>([])
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

      if (!user) return

      const { data, error } = await supabase
        .from("accounts")
        .select(PROPFIRM_ACCOUNT_FIELDS)
        .eq("user_id", user.id)
        .eq("category", "Prop Firm")

      if (error) {
        console.error(error)
        return
      }

      setAccounts(data || [])
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
        <div className="mx-auto max-w-6xl p-6 text-gray-400">Loading...</div>
      </PropfirmPageShell>
    )
  }

  if (!hasProAccess) {
    return (
      <PropfirmPageShell>
        <div className="mx-auto max-w-6xl p-6">
          <div className="rounded-xl border border-white/10 bg-[#0f172a] p-6 text-center">
            <h1 className="text-2xl font-semibold text-white">
              Prop Firm Analytics is a Pro feature
            </h1>
            <p className="mt-2 text-sm text-gray-400">
              Upgrade to Pro to unlock prop firm performance tracking.
            </p>
          </div>
        </div>
      </PropfirmPageShell>
    )
  }

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
      <div className="mx-auto max-w-6xl space-y-2.5 md:space-y-3">
        <div className="rounded-2xl border border-white/10 bg-white/10 p-3 shadow-xl shadow-black/10 backdrop-blur-md md:p-4">
          <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-300/80">
                Prop Firm Analytics
              </p>
              <h1 className="mt-0.5 text-2xl font-semibold text-white md:text-3xl">
                Prop Firm Mode
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Track rule progress, drawdown room, and account balance from one
                stabilized view.
              </p>
            </div>

            <div
              className={`inline-flex w-fit rounded-full border px-3 py-1 text-sm font-semibold ${
                status === "PASSED"
                  ? "border-green-500/30 bg-green-500/10 text-green-400"
                  : status === "FAILED"
                    ? "border-red-500/30 bg-red-500/10 text-red-400"
                    : "border-yellow-500/30 bg-yellow-500/10 text-yellow-400"
              }`}
            >
              {statusLabel}
            </div>
          </div>

          <div className="mt-3 grid gap-2 md:grid-cols-[minmax(0,420px)_1fr] md:items-center">
            <select
              value={
                selectedAccount?.id != null ? String(selectedAccount.id) : ""
              }
              onChange={(e) => {
                const selected = accounts.find(
                  (a) => String(a.id) === e.target.value
                )
                setSelectedAccount(selected ?? null)
              }}
              className="w-full rounded-lg border border-white/10 bg-[#0f172a] p-2 text-sm"
            >
              <option value="">Select Account</option>
              {accounts.map((acc) => (
                <option key={acc.id} value={String(acc.id)}>
                  {acc.name} •{" "}
                  {acc.account_size == null ? "" : String(acc.account_size)} •{" "}
                  {acc.mode}
                </option>
              ))}
            </select>

            <p className="text-sm text-gray-400 md:text-right">
              Selected:{" "}
              <span className="font-medium text-gray-200">
                {selectedAccountLabel}
              </span>
            </p>
          </div>
        </div>

        {loadingTrades && <p className="text-sm text-gray-400">Loading...</p>}

        {selectedAccount && (
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-2.5 shadow-lg shadow-black/10">
              <p className="text-xs uppercase tracking-wide text-gray-400">
                Total P&amp;L
              </p>
              <p
                className={`mt-1 text-xl font-bold tabular-nums ${
                  totalPnL >= 0 ? "text-green-400" : "text-red-400"
                }`}
              >
                {formatPropfirmUsd(totalPnL)}
              </p>
            </div>

            <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-2.5 shadow-lg shadow-black/10">
              <p className="text-xs uppercase tracking-wide text-gray-400">
                Current Balance
              </p>
              <p className="mt-1 text-xl font-bold tabular-nums text-white">
                {formatPropfirmUsd(trailingMetrics.currentBalance)}
              </p>
            </div>

            <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-2.5 shadow-lg shadow-black/10">
              <p className="text-xs uppercase tracking-wide text-gray-400">
                Distance to DD
              </p>
              <p className={`mt-1 text-xl font-bold tabular-nums ${distanceClassName}`}>
                {formatPropfirmUsd(distanceToDD)}
              </p>
            </div>

            <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-2.5 shadow-lg shadow-black/10">
              <p className="text-xs uppercase tracking-wide text-gray-400">
                Winning Days
              </p>
              <p
                className={`mt-1 text-xl font-bold tabular-nums ${
                  winningDaysTargetMet ? "text-green-400" : "text-yellow-400"
                }`}
              >
                {winningDays}/{Number(selectedAccount.winning_days) || 0}
              </p>
            </div>
          </div>
        )}

        {selectedAccount && (
          <PropfirmEquityCurve
            data={equityCurveData}
            startingBalance={startingBalance}
          />
        )}

        {selectedAccount && (
          <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-3 shadow-lg shadow-black/10">
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-base font-semibold text-white">Rule Status</h2>
              <span className="text-xs uppercase tracking-wide text-gray-500">
                Evaluation
              </span>
            </div>

            <div className="grid gap-1.5 text-sm sm:grid-cols-2">
              <div
                className={`flex items-center gap-2 rounded-lg border border-white/5 bg-white/[0.03] px-2.5 py-1.5 ${
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
                className={`flex items-center gap-2 rounded-lg border border-white/5 bg-white/[0.03] px-2.5 py-1.5 ${
                  dailyDrawdownBreached
                    ? "text-red-400"
                    : "text-green-400"
                }`}
              >
                <span>{dailyDrawdownBreached ? "❌" : "✔"}</span>
                <span className="font-medium">Daily Drawdown</span>
              </div>

              <div
                className={`flex items-center gap-2 rounded-lg border border-white/5 bg-white/[0.03] px-2.5 py-1.5 ${
                  winningDaysTargetMet
                    ? "text-green-400"
                    : "text-yellow-400"
                }`}
              >
                <span>{winningDaysTargetMet ? "✔" : "⚠"}</span>
                <span className="font-medium">Winning Days</span>
              </div>

              <div
                className={`flex items-center gap-2 rounded-lg border border-white/5 bg-white/[0.03] px-2.5 py-1.5 ${
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
          <div className="rounded-xl border border-white/10 bg-[#0f172a]/90 p-2.5 md:p-3">
            <h2 className="mb-1.5 text-base font-semibold text-white">
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
          <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-3">
            <h2 className="mb-2 text-base font-semibold text-white">
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

            <div className="mt-3 space-y-2">
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

        <div className="rounded-xl border border-white/10 bg-[#0f172a]/95 p-2.5 shadow-lg shadow-black/10 md:p-3">
          <div className="mb-1.5 flex items-center justify-between gap-2">
            <div>
              <h2 className="text-base font-semibold text-white">
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
                  className="flex items-center justify-between rounded-lg border border-white/5 bg-white/[0.03] px-2.5 py-1"
                >
                  <span className="font-medium text-gray-300">{date}</span>
                  <span
                    className={
                      pnl >= 0
                        ? "font-semibold text-green-400"
                        : "font-semibold text-red-400"
                    }
                  >
                    ${pnl.toFixed(2)}
                  </span>
                </div>
              ))
            ) : (
              <div className="rounded-lg border border-dashed border-white/10 bg-white/[0.03] px-3 py-4 text-center text-gray-400">
                No daily performance yet.
              </div>
            )}
          </div>
        </div>

        {!selectedAccount ? (
          <div className="text-gray-400">
            Select a prop firm account to view progress
          </div>
        ) : null}
      </div>
    </PropfirmPageShell>
  )
}
