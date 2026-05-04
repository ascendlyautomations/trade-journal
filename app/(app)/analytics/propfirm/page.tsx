"use client"

import { useEffect, useMemo, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { isProActive } from "@/lib/subscription"

type TradeForDay = {
  trade_date?: string | null
  entry_time?: string | null
}

const getTradingDay = (trade: TradeForDay) => {
  if (!trade.trade_date) return null

  const parts = trade.trade_date.split("-").map(Number)
  if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return null
  const [year, month, day] = parts

  let hours = 12
  let minutes = 0

  if (trade.entry_time) {
    const utc = new Date(trade.entry_time)
    if (Number.isNaN(utc.getTime())) return null

    const est = new Date(
      utc.toLocaleString("en-US", {
        timeZone: "America/New_York",
      })
    )

    hours = est.getHours()
    minutes = est.getMinutes()
  }

  const d = new Date(year, month - 1, day, hours, minutes)

  if (hours >= 18) {
    d.setDate(d.getDate() + 1)
  }

  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const da = String(d.getDate()).padStart(2, "0")

  return `${y}-${m}-${da}`
}

/** Parse `accounts.account_size` (number or strings like "50K", "50,000") to dollars. */
function parseAccountSizeToNumber(account: { account_size?: unknown }): number {
  const raw = account?.account_size
  if (raw == null || raw === "") return 0
  if (typeof raw === "number" && Number.isFinite(raw)) return raw
  const s = String(raw).trim().replace(/,/g, "")
  const k = /^([\d.]+)\s*k$/i.exec(s)
  if (k) {
    const n = Number(k[1])
    return Number.isFinite(n) ? n * 1000 : 0
  }
  const n = Number(s)
  return Number.isFinite(n) ? n : 0
}

export type TrailingDrawdownResult = {
  currentBalance: number
  peakBalance: number
  drawdownFloor: number
  distanceToDD: number
  /** Largest (peak − balance) observed after any trade (for “max DD used” vs limit). */
  maxDrawdownUsed: number
  /** True if at any point after a trade, balance fell below the trailing drawdown floor. */
  breachedTrailingDD: boolean
}

export type ConsistencyRuleResult = {
  biggestWin: number
  totalProfit: number
  allowedMax: number
  isConsistent: boolean
  ruleActive: boolean
}

/** Drop duplicate trade rows (same `id`) so PnL is not double-counted. */
function dedupeTradesById(trades: any[]): any[] {
  const seen = new Set<string>()
  const out: any[] = []
  for (const t of trades) {
    const id = t?.id
    if (id != null && id !== "") {
      const key = String(id)
      if (seen.has(key)) continue
      seen.add(key)
    }
    out.push(t)
  }
  return out
}

/**
 * Trailing drawdown: drawdown floor moves **only** when equity makes a **new** peak
 * (`drawdownFloor = peakBalance - maxDrawdown` at that moment only). Floor never
 * moves on losses; peak never decreases.
 */
export function computeTrailingDrawdown(
  trades: any[],
  startingBalance: number,
  maxDrawdown: number
): TrailingDrawdownResult {
  const maxDd = Number(maxDrawdown) || 0

  const uniqueTrades = dedupeTradesById(trades)
  const tradesSorted = [...uniqueTrades].sort(
    (a, b) => +new Date(a.created_at) - +new Date(b.created_at)
  )

  console.log("STARTING VALUES:", {
    startingBalance,
    maxDrawdown: maxDd,
    trades: tradesSorted.map((t) => ({
      pnl: t.pnl,
      created_at: t.created_at,
    })),
  })

  let balance = startingBalance
  let peakBalance = startingBalance
  let drawdownFloor = startingBalance - maxDd
  let maxDrawdownUsed = 0
  let breachedTrailingDD = false

  for (const trade of tradesSorted) {
    const pnl = parseFloat(String(trade.pnl ?? "")) || 0

    console.log("TRADE STEP:", {
      pnl: trade.pnl,
      balanceBefore: balance,
      balanceAfter: balance + pnl,
      peakBefore: peakBalance,
    })

    balance += pnl

    if (balance > peakBalance) {
      peakBalance = balance
      drawdownFloor = peakBalance - maxDd
    }

    console.log("AFTER UPDATE:", {
      balance,
      peakBalance,
      drawdownFloor,
    })

    const ddFromPeak = peakBalance - balance
    if (ddFromPeak > maxDrawdownUsed) {
      maxDrawdownUsed = ddFromPeak
    }

    if (maxDd > 0 && balance < drawdownFloor) {
      breachedTrailingDD = true
    }
  }

  const distanceToDD = balance - drawdownFloor

  return {
    currentBalance: balance,
    peakBalance,
    drawdownFloor,
    distanceToDD,
    maxDrawdownUsed,
    breachedTrailingDD,
  }
}

/** `consistency_percent` from account rules (DB column `consistency`). */
export function computeConsistencyRule(
  trades: any[],
  consistencyPercent: number
): ConsistencyRuleResult {
  const pct = Number(consistencyPercent)
  const ruleActive = Number.isFinite(pct) && pct > 0

  const winningTrades = trades.filter((t) => Number(t.pnl) > 0)
  const totalProfit = winningTrades.reduce(
    (sum, t) => sum + Number(t.pnl || 0),
    0
  )
  const biggestWin =
    winningTrades.length > 0
      ? Math.max(...winningTrades.map((t) => Number(t.pnl || 0)))
      : 0

  const allowedMax = ruleActive ? totalProfit * (pct / 100) : 0
  const isConsistent = !ruleActive || biggestWin <= allowedMax

  return {
    biggestWin,
    totalProfit,
    allowedMax,
    isConsistent,
    ruleActive,
  }
}

function formatUsd(n: number) {
  const sign = n < 0 ? "-" : ""
  return `${sign}$${Math.abs(n).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })}`
}

export default function PropFirmPage() {
  const [planChecked, setPlanChecked] = useState(false)
  const [hasProAccess, setHasProAccess] = useState(false)
  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [loadingTrades, setLoadingTrades] = useState(false)

  const filteredTrades = [...trades].sort((a, b) => {
    const da = String(a.trade_date ?? "")
    const db = String(b.trade_date ?? "")
    const byDate = da.localeCompare(db)
    if (byDate !== 0) return byDate
    const at = a.entry_time ? new Date(a.entry_time).getTime() : 0
    const bt = b.entry_time ? new Date(b.entry_time).getTime() : 0
    return at - bt
  })

  const dailyPnLMap: Record<string, number> = {}

  filteredTrades.forEach((t) => {
    const day = getTradingDay(t)
    if (!day) return

    dailyPnLMap[day] = (dailyPnLMap[day] || 0) + Number(t.pnl || 0)
  })

  const dailyRows = Object.entries(dailyPnLMap).sort(([a], [b]) =>
    a.localeCompare(b)
  )

  const winningDays = Object.values(dailyPnLMap).filter(
    (pnl) => pnl > 0
  ).length

  const nowEST = new Date(
    new Date().toLocaleString("en-US", {
      timeZone: "America/New_York",
    })
  )
  const todayKey = `${nowEST.getFullYear()}-${String(
    nowEST.getMonth() + 1
  ).padStart(2, "0")}-${String(nowEST.getDate()).padStart(2, "0")}`
  const todayPnL = dailyPnLMap[todayKey] || 0

  const dayPnLValues = Object.values(dailyPnLMap)
  const worstDay =
    dayPnLValues.length > 0 ? Math.min(...dayPnLValues) : 0

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
        .select("*")
        .eq("user_id", user.id)
        .eq("category", "Prop Firm")

      if (error) {
        console.error(error)
        return
      }

      const list = data || []
      console.log("ACCOUNTS LOADED:", list)
      setAccounts(list)
    }

    loadAccounts()
  }, [planChecked, hasProAccess])

  useEffect(() => {
    if (!planChecked || !hasProAccess) return
    if (!selectedAccount) return

    setTrades([])

    async function loadTrades() {
      setLoadingTrades(true)
      try {
        console.log("FETCHING TRADES FOR:", selectedAccount.account_number)
        const { data, error } = await supabase
          .from("trades")
          .select("*")
          .eq("account_id", selectedAccount.id)
          .order("trade_date", { ascending: true })
          .order("entry_time", { ascending: true })

        if (error) {
          console.error(error)
          return
        }

        console.log("TRADES RESULT:", data)
        setTrades(data || [])
      } finally {
        setLoadingTrades(false)
      }
    }

    loadTrades()
  }, [selectedAccount, planChecked, hasProAccess])

  const startingBalance = useMemo(() => {
    if (!selectedAccount) return 0
    return parseAccountSizeToNumber(selectedAccount)
  }, [selectedAccount])

  const trailingMetrics = useMemo((): TrailingDrawdownResult => {
    if (!selectedAccount) {
      return {
        currentBalance: 0,
        peakBalance: 0,
        drawdownFloor: 0,
        distanceToDD: 0,
        maxDrawdownUsed: 0,
        breachedTrailingDD: false,
      }
    }
    const maxDd = Number(selectedAccount.max_drawdown) || 0
    return computeTrailingDrawdown(trades, startingBalance, maxDd)
  }, [trades, selectedAccount, startingBalance])

  const consistencyMetrics = useMemo((): ConsistencyRuleResult => {
    if (!selectedAccount) {
      return {
        biggestWin: 0,
        totalProfit: 0,
        allowedMax: 0,
        isConsistent: true,
        ruleActive: false,
      }
    }
    const pct = Number(selectedAccount.consistency) || 0
    return computeConsistencyRule(trades, pct)
  }, [trades, selectedAccount])

  if (!planChecked) {
    return <div className="mx-auto max-w-6xl p-6 text-gray-400">Loading...</div>
  }

  if (!hasProAccess) {
    return (
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
    )
  }

  const totalPnL = filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

  const drawdownUsed = trailingMetrics.maxDrawdownUsed

  const progressPercent = selectedAccount?.profit_target
    ? Math.min((totalPnL / selectedAccount.profit_target) * 100, 100)
    : 0

  const worstDailyLossUsed =
    worstDay < 0 ? Math.abs(worstDay) : 0

  const isPassed =
    selectedAccount && totalPnL >= selectedAccount.profit_target

  const maxDdLimit = Number(selectedAccount?.max_drawdown) || 0
  const isFailed =
    selectedAccount &&
    maxDdLimit > 0 &&
    (trailingMetrics.breachedTrailingDD || trailingMetrics.distanceToDD < 0)

  const status = isFailed
    ? "FAILED"
    : isPassed
      ? "PASSED"
      : "IN PROGRESS"

  const ddPercent =
    maxDdLimit > 0 ? Math.min((drawdownUsed / maxDdLimit) * 100, 100) : 0

  const distanceToDD = trailingMetrics.distanceToDD
  const distanceDanger =
    maxDdLimit > 0 &&
    distanceToDD >= 0 &&
    distanceToDD < 0.2 * maxDdLimit
  const distanceClassName =
    maxDdLimit <= 0
      ? "text-gray-400"
      : distanceToDD < 0 || distanceDanger
        ? "text-red-400"
        : "text-green-400"

  const formatAccount = (acc: any) => {
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

  return (
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
          console.log("SELECTED ACCOUNT:", selected)
          setSelectedAccount(selected ?? null)
        }}
        className="mb-6 w-full max-w-md rounded border border-white/10 bg-[#0f172a] p-2"
      >
        <option value="">Select Account</option>
        {accounts.map((acc) => (
          <option key={acc.id} value={String(acc.id)}>
            {acc.name} • {acc.account_size} • {acc.mode}
          </option>
        ))}
      </select>

      <p className="text-sm text-gray-400">
        Selected: {formatAccount(selectedAccount)}
      </p>

      {loadingTrades && <p className="text-sm text-gray-400">Loading...</p>}

      {selectedAccount && (
        <div className="mb-6 rounded-xl border border-white/10 bg-[#0f172a] p-4">
          <h2 className="mb-3 text-lg">Account Rules</h2>

          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span>Account size (starting balance)</span>
              <span>
                {startingBalance > 0 ? formatUsd(startingBalance) : "—"}
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
                {formatUsd(drawdownUsed)}
              </span>
            </div>

            <div className="flex justify-between">
              <span>Drawdown Floor</span>
              <span>{formatUsd(trailingMetrics.drawdownFloor)}</span>
            </div>

            <div className="flex justify-between">
              <span>Current Balance</span>
              <span>{formatUsd(trailingMetrics.currentBalance)}</span>
            </div>

            <div className="flex justify-between">
              <span>Distance to DD</span>
              <span className={distanceClassName}>
                {formatUsd(distanceToDD)}
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
              <p className="mb-2 font-medium text-gray-300">
                Consistency Rule
              </p>
              <div className="flex justify-between">
                <span>Biggest Trade</span>
                <span>{formatUsd(consistencyMetrics.biggestWin)}</span>
              </div>
              <div className="flex justify-between">
                <span>Allowed Max</span>
                <span>
                  {consistencyMetrics.ruleActive
                    ? formatUsd(consistencyMetrics.allowedMax)
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
            worstDailyLossUsed > selectedAccount.daily_drawdown && (
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
                worstDailyLossUsed > selectedAccount.daily_drawdown
                  ? "text-red-400"
                  : "text-green-400"
              }
            >
              {worstDailyLossUsed > selectedAccount.daily_drawdown ? "❌" : "✔"}{" "}
              Daily Drawdown
            </div>

            <div
              className={
                winningDays >= selectedAccount.winning_days
                  ? "text-green-400"
                  : "text-yellow-400"
              }
            >
              {winningDays >= selectedAccount.winning_days ? "✔" : "⚠"} Winning
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
      <div className="hidden">{accounts.length + filteredTrades.length}</div>
    </div>
  )
}
