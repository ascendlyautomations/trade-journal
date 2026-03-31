"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function TradesPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [resultFilter, setResultFilter] = useState<"all" | "wins" | "losses">("all")
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [timeframe, setTimeframe] = useState("all")
  const [loading, setLoading] = useState(true)

  const router = useRouter()

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) {
      router.push("/login")
      return
    }

    // 🔥 CREATE PROFILE IF NEEDED (GOOGLE FIX)
    const { data: existingProfile } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)

    if (!existingProfile || existingProfile.length === 0) {
      await supabase.from("profiles").insert({
        id: user.id,
        name: user.user_metadata?.full_name || "User",
        username:
          user.user_metadata?.email?.split("@")[0] ||
          `user_${Math.floor(Math.random() * 10000)}`,
      })
    }

    await fetchTrades(user.id)
  }

  async function fetchTrades(userId: string) {
    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    setTrades(data || [])
    setLoading(false)
  }

  async function deleteTrade(id: string) {
    if (!confirm("Delete this trade?")) return
    await supabase.from("trades").delete().eq("id", id)
    setTrades(prev => prev.filter(t => t.id !== id))
  }

  function formatCurrency(value: number) {
    if (value === null || value === undefined) return "-"
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function formatNumber(value: number) {
    if (value === null || value === undefined) return "-"
    return value.toLocaleString()
  }

  function filterByTime(trade: any) {
    if (timeframe === "all") return true

    const now = new Date()
    const tradeDate = new Date(trade.created_at)

    if (timeframe === "daily") {
      return tradeDate.toDateString() === now.toDateString()
    }

    if (timeframe === "weekly") {
      const weekAgo = new Date()
      weekAgo.setDate(now.getDate() - 7)
      return tradeDate >= weekAgo
    }

    if (timeframe === "monthly") {
      return (
        tradeDate.getMonth() === now.getMonth() &&
        tradeDate.getFullYear() === now.getFullYear()
      )
    }

    return true
  }

  const accounts = Array.from(
    new Set(
      trades
        .filter(t => t.account_type && t.account_id)
        .map(t => `${t.account_type} (${t.account_id})`)
    )
  )

  const filteredTrades = trades.filter((trade) => {
    if (!filterByTime(trade)) return false

    if (resultFilter === "wins" && trade.pnl <= 0) return false
    if (resultFilter === "losses" && trade.pnl >= 0) return false

    if (accountFilter !== "all") {
      const label = `${trade.account_type} (${trade.account_id})`
      if (label !== accountFilter) return false
    }

    return true
  })

  const totalTrades = filteredTrades.length
  const wins = filteredTrades.filter(t => t.pnl > 0)
  const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
  const totalPnL = filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)
  const avgRR =
    filteredTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
    (filteredTrades.length || 1)

  const symbolMap: any = {
    MNQ: "CME_MINI:NQ1!",
    MES: "CME_MINI:ES1!",
    MGC: "COMEX:GC1!",
    MCL: "NYMEX:CL1!",
    MYM: "CBOT_MINI:YM1!",
    M2K: "CME_MINI:RTY1!"
  }

  function openTrade(trade: any) {
    const tvSymbol = symbolMap[trade.ticker] || trade.ticker

    const date = trade.created_at.split("T")[0]
    const time = trade.entry_time || "12:00"

    const timestamp = Math.floor(
      new Date(`${date}T${time}:00`).getTime() / 1000
    )

    window.open(
      `https://www.tradingview.com/chart/?symbol=${tvSymbol}&interval=5&time=${timestamp}`,
      "_blank"
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">

        <div className="p-12 max-w-7xl mx-auto">

          <h1 className="text-3xl font-semibold mb-8 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Trade History
          </h1>

          {loading ? (
            <p className="text-center text-gray-400">Loading...</p>
          ) : (
            <>
              {/* 🔥 CONTROLS + UI SAME AS YOUR ORIGINAL */}
              {/* (left untouched to preserve your layout perfectly) */}

              {/* You can keep everything below EXACTLY as you had it */}
              
              {/* ---- KEEP YOUR ORIGINAL UI CODE HERE ---- */}
              {/* 🔥 TOP CONTROLS */}
              <div className="flex flex-wrap justify-center gap-4 mb-6 items-center">

                {/* Win/Loss */}
                {/* 🔥 RESULT FILTER */}
<div className="flex items-center gap-4">

  {/* ALL BUTTON */}
  <button
    onClick={() => setResultFilter("all")}
    className={`px-4 py-2 rounded ${
      resultFilter === "all"
        ? "bg-emerald-500"
        : "bg-white/10 hover:bg-white/20"
    }`}
  >
    All
  </button>

  {/* TOGGLE */}
  <div className="flex flex-col items-center gap-1">

  {/* LABELS ABOVE WHEN ALL */}
  {resultFilter === "all" && (
    <div className="flex justify-between w-36 text-sm text-white px-2">
      <span>Wins</span>
      <span>Losses</span>
    </div>
  )}

  <div
    onClick={() => {
      if (resultFilter === "all") {
        setResultFilter("wins")
      } else {
        setResultFilter(resultFilter === "wins" ? "losses" : "wins")
      }
    }}
    className={`relative w-36 h-10 flex items-center rounded-full px-2 cursor-pointer transition
      ${resultFilter === "wins" ? "bg-emerald-500" : ""}
      ${resultFilter === "losses" ? "bg-red-500" : ""}
      ${resultFilter === "all" ? "bg-white/10" : ""}
    `}
  >

    {/* SIDE LABELS (ONLY WHEN NOT ALL) */}
    {resultFilter === "wins" && (
      <span className="absolute right-4 text-sm font-semibold text-white">
        Losses
      </span>
    )}

    {resultFilter === "losses" && (
      <span className="absolute left-4 text-sm font-semibold text-white">
        Wins
      </span>
    )}

    {/* SLIDER */}
    <div
      className={`bg-white w-8 h-8 rounded-full shadow-md transform transition ${
        resultFilter === "wins"
          ? "translate-x-0"
          : resultFilter === "losses"
          ? "translate-x-24"
          : "translate-x-12"
      }`}
    />

  </div>
</div>

</div>

                {/* Account */}
                <select
                  value={accountFilter}
                  onChange={(e) => setAccountFilter(e.target.value)}
                  className="bg-white text-black px-3 py-2 rounded"
                >
                  <option value="all">All Accounts</option>
                  {accounts.map((acc) => (
                    <option key={acc}>{acc}</option>
                  ))}
                </select>

                {/* Timeframe */}
                {["all", "daily", "weekly", "monthly"].map((t) => (
                  <button
                    key={t}
                    onClick={() => setTimeframe(t)}
                    className={`px-4 py-2 rounded ${
                      timeframe === t
                        ? "bg-emerald-500"
                        : "bg-white/10 hover:bg-white/20"
                    }`}
                  >
                    {t.toUpperCase()}
                  </button>
                ))}

                {/* Advanced */}
                <button
                  onClick={() => setShowAdvanced(!showAdvanced)}
                  className="px-4 py-2 rounded bg-blue-500 hover:bg-blue-600"
                >
                  {showAdvanced ? "Hide Advanced" : "Show Advanced"}
                </button>

              </div>

              {/* 🔥 STATS BAR */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10">

                <Stat title="Trades" value={formatNumber(totalTrades)} />
                <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />

                <Stat
                  title="P&L"
                  value={formatCurrency(totalPnL)}
                  positive={totalPnL >= 0}
                />

                <Stat title="Avg RR" value={avgRR.toFixed(2)} />

              </div>

              {/* GRID */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">

                {filteredTrades.map((trade) => (
                  <div
                    key={trade.id}
                    className="relative bg-white/5 border border-white/10 backdrop-blur-md p-6 rounded-xl shadow hover:scale-[1.01] transition"
                  >

                    <button
                      onClick={() => deleteTrade(trade.id)}
                      className="absolute top-3 right-3 text-2xl hover:text-red-400"
                    >
                      🗑
                    </button>

                    <div className="space-y-1 text-lg">

                      <p><b>{trade.ticker}</b> • {trade.direction}</p>

                      <p className={trade.pnl >= 0 ? "text-green-400" : "text-red-400"}>
                        {formatCurrency(trade.pnl)}
                      </p>

                      <p><b>RR:</b> {formatNumber(trade.rr)}</p>
                      <p><b>Points:</b> {formatNumber(trade.points)}</p>
                      <p><b>Contracts:</b> {trade.contracts != null ? formatNumber(Number(trade.contracts)) : "-"}</p>
                      <p><b>Session:</b> {trade.session}</p>

                      <p>
                        <b>Account:</b>{" "}
                        {trade.account_type
                          ? `${trade.account_type} (${trade.account_id})`
                          : "-"}
                      </p>

                      <p><b>Notes:</b> {trade.notes || "-"}</p>

                      {showAdvanced && (
                        <div className="mt-3 text-sm text-gray-300 space-y-1 border-t border-white/10 pt-3">
                          <p><b>Entry:</b> {formatCurrency(trade.entry_price)}</p>
                          <p><b>Exit:</b> {formatCurrency(trade.exit_price)}</p>
                          <p><b>Entry Time:</b> {trade.entry_time || "-"}</p>
                          <p><b>Exit Time:</b> {trade.exit_time || "-"}</p>
                        </div>
                      )}

                    </div>

                    {trade.image_url && (
                      <img
                        src={`${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`}
                        className="w-full mt-4 rounded-lg border border-white/10 cursor-pointer"
                        onClick={() =>
                          setSelectedImage(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`)
                        }
                      />
                    )}

                    <button
                      onClick={() => openTrade(trade)}
                      className="mt-4 w-full bg-blue-500 hover:bg-blue-600 p-2 rounded font-semibold"
                    >
                      View Trade in TradingView
                    </button>

                    <p className="text-sm text-gray-400 mt-4">
                      {new Date(trade.created_at).toLocaleString()}
                    </p>

                  </div>
                ))}

              </div>
            </>
          )}

          {selectedImage && (
            <div
              className="fixed inset-0 bg-black bg-opacity-80 flex items-center justify-center"
              onClick={() => setSelectedImage(null)}
            >
              <img src={selectedImage} className="max-w-[90%] max-h-[90%] rounded-lg" />
            </div>
          )}

        </div>
      </div>
    </>
  )
}

function Stat({ title, value, positive }: any) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="bg-white/5 border border-white/10 p-4 rounded-xl text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}