"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"

export default function PropFirmPage() {
  const [accounts, setAccounts] = useState<any[]>([])
  const [selectedAccount, setSelectedAccount] = useState<any | null>(null)
  const [trades, setTrades] = useState<any[]>([])

  const dailyPnLMap: Record<string, number> = {}

  trades.forEach((t) => {
    const date = t.created_at.split("T")[0]

    if (!dailyPnLMap[date]) {
      dailyPnLMap[date] = 0
    }

    dailyPnLMap[date] += t.pnl || 0
  })

  const dailyRows = Object.entries(dailyPnLMap)

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

      setAccounts(data || [])
    }

    loadAccounts()
  }, [])

  useEffect(() => {
    if (!selectedAccount) return

    async function loadTrades() {
      const { data, error } = await supabase
        .from("trades")
        .select("*")
        .eq("account_id", selectedAccount.account_number)

      if (error) {
        console.error(error)
        return
      }

      setTrades(data || [])
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

  const winningDays = new Set(
    trades.filter((t) => t.pnl > 0).map((t) => t.created_at.split("T")[0])
  ).size

  const progressPercent = selectedAccount?.profit_target
    ? Math.min((totalPnL / selectedAccount.profit_target) * 100, 100)
    : 0

  const today = new Date().toISOString().split("T")[0]

  const todayLoss = trades
    .filter((t) => t.created_at.startsWith(today))
    .reduce((sum, t) => sum + (t.pnl || 0), 0)

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

  return (
    <div className="p-6 text-white">
      <h1 className="text-2xl font-semibold mb-6">
        Prop Firm Mode
      </h1>

      <div className="mb-4 text-lg font-semibold">
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
        value={selectedAccount?.id || ""}
        onChange={(e) => {
          const acc = accounts.find((a) => a.id === Number(e.target.value))
          setSelectedAccount(acc ?? null)
        }}
        className="w-full max-w-md p-2 rounded bg-[#0f172a] border border-white/10 mb-6"
      >
        <option value="">Select Account</option>
        {accounts.map((acc) => (
          <option key={acc.id} value={acc.id}>
            {acc.name} • {acc.account_size} • {acc.mode}
          </option>
        ))}
      </select>

      {selectedAccount && (
        <div className="bg-[#0f172a] border border-white/10 rounded-xl p-4 mb-6">
          <h2 className="text-lg mb-3">Account Rules</h2>

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
        <div className="bg-[#0f172a] border border-white/10 rounded-xl p-4">
          <h2 className="text-lg mb-3">Progress</h2>

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
              <span className="text-red-400">
                ${drawdownUsed}
              </span>
            </div>

            <div className="flex justify-between">
              <span>Winning Days</span>
              <span>{winningDays}</span>
            </div>
          </div>

          <div className="mt-4">
            <div className="w-full bg-white/10 h-2 rounded">
              <div
                className="bg-green-500 h-2 rounded"
                style={{ width: `${progressPercent}%` }}
              />
            </div>
          </div>

          <div className="mt-3">
            <div className="w-full bg-white/10 h-2 rounded">
              <div
                className="bg-red-500 h-2 rounded"
                style={{ width: `${ddPercent}%` }}
              />
            </div>
          </div>

          {selectedAccount && drawdownUsed > selectedAccount.max_drawdown && (
            <div className="mt-4 text-red-400 text-sm">
              ⚠️ Max drawdown exceeded
            </div>
          )}

          {selectedAccount && Math.abs(todayLoss) > selectedAccount.daily_drawdown && (
            <div className="mt-2 text-red-400 text-sm">
              ⚠️ Daily drawdown exceeded
            </div>
          )}
        </div>
      )}

      {selectedAccount && (
        <div className="bg-[#0f172a] border border-white/10 rounded-xl p-4 mt-6">
          <h2 className="text-lg mb-3">Rule Status</h2>

          <div className="space-y-2 text-sm">
            <div className={drawdownUsed > selectedAccount.max_drawdown ? "text-red-400" : "text-green-400"}>
              {drawdownUsed > selectedAccount.max_drawdown ? "❌" : "✔"} Max Drawdown
            </div>

            <div className={Math.abs(todayLoss) > selectedAccount.daily_drawdown ? "text-red-400" : "text-green-400"}>
              {Math.abs(todayLoss) > selectedAccount.daily_drawdown ? "❌" : "✔"} Daily Drawdown
            </div>

            <div className={winningDays >= selectedAccount.winning_days ? "text-green-400" : "text-yellow-400"}>
              {winningDays >= selectedAccount.winning_days ? "✔" : "⚠"} Winning Days
            </div>
          </div>
        </div>
      )}

      <div className="bg-[#0f172a] border border-white/10 rounded-xl p-4 mt-6">
        <h2 className="text-lg mb-3">Daily Performance</h2>

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
