"use client"

import { useEffect, useMemo, useState, type ReactNode } from "react"
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

function PropfirmPageShell({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
      <div className="w-full px-2 pb-6 pt-3 text-white md:px-4 md:pb-10">{children}</div>
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
      <div className="mx-auto max-w-6xl space-y-6">
        <h1 className="text-2xl font-semibold">Prop Firm Mode</h1>

        <div className="text-lg font-semibold">
          Status:{" "}
          <span
            className={
              status === "PASSED"
                ? "text-green-400"
                : status === "FAILED"
                  ? "text-red-400"
                  : "text-yellow-400"
            }
          >
            {status}
          </span>
        </div>

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
          className="mb-6 w-full max-w-md rounded border border-white/10 bg-[#0f172a] p-2"
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

        <p className="text-sm text-gray-400">
          Selected: {selectedAccountLabel}
        </p>

        {loadingTrades && <p className="text-sm text-gray-400">Loading...</p>}

        {selectedAccount && (
          <div className="mb-6 rounded-xl border border-white/10 bg-[#0f172a] p-4">
            <h2 className="mb-3 text-lg">Account Rules</h2>

            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span>Account size (starting balance)</span>
                <span>
                  {startingBalance > 0 ? formatPropfirmUsd(startingBalance) : "—"}
                </span>
              </div>

              <div className="flex justify-between">
                <span>Consistency</span>
                <span>{selectedAccount.consistency || 0}%</span>
              </div>

              <div className="flex justify-between">
                <span>Max Drawdown</span>
                <span>${selectedAccount.max_drawdown}</span>
              </div>

              <div className="flex justify-between">
                <span>Daily Drawdown</span>
                <span>${selectedAccount.daily_drawdown}</span>
              </div>

              <div className="flex justify-between">
                <span>Profit Target</span>
                <span>${selectedAccount.profit_target}</span>
              </div>

              <div className="flex justify-between">
                <span>Winning Days</span>
                <span>{selectedAccount.winning_days}</span>
              </div>
            </div>
          </div>
        )}

        {selectedAccount && (
          <div className="rounded-xl border border-white/10 bg-[#0f172a] p-4">
            <h2 className="mb-3 text-lg">Progress</h2>

            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span>Total P&L</span>
                <span className={totalPnL >= 0 ? "text-green-400" : "text-red-400"}>
                  ${totalPnL}
                </span>
              </div>

              <div className="flex justify-between">
                <span>Profit Target</span>
                <span>${selectedAccount.profit_target}</span>
              </div>

              <div className="flex justify-between">
                <span>Max Drawdown Used</span>
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

              <div className="flex justify-between">
                <span>Drawdown Floor</span>
                <span>{formatPropfirmUsd(trailingMetrics.drawdownFloor)}</span>
              </div>

              <div className="flex justify-between">
                <span>Current Balance</span>
                <span>{formatPropfirmUsd(trailingMetrics.currentBalance)}</span>
              </div>

              <div className="flex justify-between">
                <span>Distance to DD</span>
                <span className={distanceClassName}>
                  {formatPropfirmUsd(distanceToDD)}
                </span>
              </div>

              <div className="flex justify-between">
                <span>Winning Days</span>
                <span>{winningDays}</span>
              </div>

              <div className="flex justify-between">
                <span>Today P&L</span>
                <span className={todayPnL >= 0 ? "text-green-400" : "text-red-400"}>
                  ${todayPnL.toFixed(2)}
                </span>
              </div>

              <div className="mt-3 border-t border-white/10 pt-3">
                <p className="mb-2 font-medium text-gray-300">Consistency Rule</p>
                <div className="flex justify-between">
                  <span>Biggest Trade</span>
                  <span>{formatPropfirmUsd(consistencyMetrics.biggestWin)}</span>
                </div>
                <div className="flex justify-between">
                  <span>Allowed Max</span>
                  <span>
                    {consistencyMetrics.ruleActive
                      ? formatPropfirmUsd(consistencyMetrics.allowedMax)
                      : "—"}
                  </span>
                </div>
                <p
                  className={
                    !consistencyMetrics.ruleActive
                      ? "mt-2 text-gray-400"
                      : consistencyMetrics.isConsistent
                        ? "mt-2 text-green-400"
                        : "mt-2 text-red-400"
                  }
                >
                  {!consistencyMetrics.ruleActive
                    ? "Set consistency % in account rules to track."
                    : consistencyMetrics.isConsistent
                      ? "✔ Consistent"
                      : "✖ Not Consistent"}
                </p>
              </div>
            </div>

            <div className="mt-4">
              <div className="h-2 w-full rounded bg-white/10">
                <div
                  className="h-2 rounded bg-green-500"
                  style={{ width: `${progressPercent}%` }}
                />
              </div>
            </div>

            <div className="mt-3">
              <div className="h-2 w-full rounded bg-white/10">
                <div
                  className="h-2 rounded bg-red-500"
                  style={{ width: `${ddPercent}%` }}
                />
              </div>
            </div>

            {selectedAccount &&
              maxDdLimit > 0 &&
              trailingMetrics.breachedTrailingDD && (
                <div className="mt-4 text-sm text-red-400">
                  ⚠️ Trailing max drawdown breached (balance below drawdown floor)
                </div>
              )}

            {selectedAccount &&
              dailyDrawdownBreached && (
                <div className="mt-2 text-sm text-red-400">
                  ⚠️ Daily drawdown exceeded
                </div>
              )}
          </div>
        )}

        {selectedAccount && (
          <div className="mt-6 rounded-xl border border-white/10 bg-[#0f172a] p-4">
            <h2 className="mb-3 text-lg">Rule Status</h2>

            <div className="space-y-2 text-sm">
              <div
                className={
                  maxDdLimit > 0 && trailingMetrics.breachedTrailingDD
                    ? "text-red-400"
                    : "text-green-400"
                }
              >
                {maxDdLimit > 0 && trailingMetrics.breachedTrailingDD ? "❌" : "✔"}{" "}
                Max Drawdown
              </div>

              <div
                className={
                  dailyDrawdownBreached
                    ? "text-red-400"
                    : "text-green-400"
                }
              >
                {dailyDrawdownBreached ? "❌" : "✔"}{" "}
                Daily Drawdown
              </div>

              <div
                className={
                  winningDaysTargetMet
                    ? "text-green-400"
                    : "text-yellow-400"
                }
              >
                {winningDaysTargetMet ? "✔" : "⚠"} Winning
                Days
              </div>

              <div
                className={
                  !consistencyMetrics.ruleActive
                    ? "text-gray-400"
                    : consistencyMetrics.isConsistent
                      ? "text-green-400"
                      : "text-red-400"
                }
              >
                {!consistencyMetrics.ruleActive
                  ? "—"
                  : consistencyMetrics.isConsistent
                    ? "✔"
                    : "✖"}{" "}
                Consistency
              </div>
            </div>
          </div>
        )}

        <div className="mt-6 rounded-xl border border-white/10 bg-[#0f172a] p-4">
          <h2 className="mb-3 text-lg">Daily Performance</h2>

          <div className="space-y-2 text-sm">
            {dailyRows.map(([date, pnl]) => (
              <div key={date} className="flex justify-between">
                <span>{date}</span>
                <span className={pnl >= 0 ? "text-green-400" : "text-red-400"}>
                  ${pnl.toFixed(2)}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="text-gray-400">
          Select a prop firm account to view progress
        </div>
      </div>
    </PropfirmPageShell>
  )
}
