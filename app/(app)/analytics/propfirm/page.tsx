"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"

/**
 * Trading day from user-selected date + entry_time (noon if missing),
 * interpreted in EST, with >= 6PM → next calendar day.
 */
function getTradingDay(trade: Record<string, unknown>): string | null {
  if (!trade.date) return null

  const dateOnly = String(trade.date).trim().split("T")[0]
  if (!dateOnly) return null

  let d: Date
  const etRaw = trade.entry_time
  if (etRaw != null && String(etRaw).trim() !== "") {
    const et = String(etRaw).trim()
    if (et.includes("T")) {
      d = new Date(et)
    } else {
      const time = et.length >= 5 ? et.slice(0, 5) : "12:00"
      d = new Date(`${dateOnly}T${time.length === 5 ? `${time}:00` : time}`)
    }
  } else {
    d = new Date(`${dateOnly}T12:00:00`)
  }

  if (Number.isNaN(d.getTime())) return null

  const est = new Date(
    d.toLocaleString("en-US", { timeZone: "America/New_York" })
  )

  const hours = est.getHours()

  if (hours >= 18) {
    est.setDate(est.getDate() + 1)
  }

  return est.toISOString().split("T")[0]
}

export default function PropFirmPage() {
  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [loadingTrades, setLoadingTrades] = useState(false)

  const filteredTrades = trades

  const dailyPnLMap: Record<string, number> = {}

  filteredTrades.forEach((t) => {
    const day = getTradingDay(t as Record<string, unknown>)
    if (!day) return

    if (!dailyPnLMap[day]) {
      dailyPnLMap[day] = 0
    }

    dailyPnLMap[day] += Number(t.pnl || 0)
  })

  const dailyRows = Object.entries(dailyPnLMap)

  const winningDays = Object.values(dailyPnLMap).filter(
    (pnl) => pnl > 0
  ).length

  const dayPnLValues = Object.values(dailyPnLMap)
  const worstDay =
    dayPnLValues.length > 0 ? Math.min(...dayPnLValues) : 0

  console.log("TRADING DAYS:", dailyPnLMap)

  useEffect(() => {
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
  }, [])

  useEffect(() => {
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
          .order("date", { ascending: true })
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
  }, [selectedAccount])

  const totalPnL = trades.reduce((sum, t) => sum + (t.pnl || 0), 0)

  let runningPnL = 0
  let peak = 0
  let maxDrawdown = 0

  trades.forEach((t) => {
    runningPnL += t.pnl || 0

    if (runningPnL > peak) {
      peak = runningPnL
    }

    const dd = runningPnL - peak

    if (dd < maxDrawdown) {
      maxDrawdown = dd
    }
  })

  const drawdownUsed = Math.abs(maxDrawdown)

  const progressPercent = selectedAccount?.profit_target
    ? Math.min((totalPnL / selectedAccount.profit_target) * 100, 100)
    : 0

  const worstDailyLossUsed =
    worstDay < 0 ? Math.abs(worstDay) : 0

  const isPassed =
    selectedAccount && totalPnL >= selectedAccount.profit_target

  const isFailed =
    selectedAccount && drawdownUsed > selectedAccount.max_drawdown

  const status = isFailed
    ? "FAILED"
    : isPassed
      ? "PASSED"
      : "IN PROGRESS"

  const ddPercent = selectedAccount?.max_drawdown
    ? Math.min((drawdownUsed / selectedAccount.max_drawdown) * 100, 100)
    : 0

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
              <span className="text-red-400">${drawdownUsed}</span>
            </div>

            <div className="flex justify-between">
              <span>Winning Days</span>
              <span>{winningDays}</span>
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

          {selectedAccount && drawdownUsed > selectedAccount.max_drawdown && (
            <div className="mt-4 text-sm text-red-400">⚠️ Max drawdown exceeded</div>
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
                drawdownUsed > selectedAccount.max_drawdown
                  ? "text-red-400"
                  : "text-green-400"
              }
            >
              {drawdownUsed > selectedAccount.max_drawdown ? "❌" : "✔"} Max
              Drawdown
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
      <div className="hidden">{accounts.length + trades.length}</div>
    </div>
  )
}
