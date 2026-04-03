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
  const [selectedDate, setSelectedDate] = useState("")

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
      let referredBy: string | null = null

      try {
        const storedCode = typeof window !== "undefined"
          ? window.localStorage.getItem("referral_code")
          : null

        if (storedCode) {
          const { data: ref } = await supabase
            .from("profiles")
            .select("id")
            .eq("referral_code", storedCode)
            .single()

          if (ref?.id) {
            referredBy = ref.id
          }
        }
      } catch (e) {
        console.error("Referral lookup failed:", e)
      }

      function generateReferralCode() {
        return Math.random().toString(36).substring(2, 8)
      }

      await supabase.from("profiles").insert({
        id: user.id,
        name: user.user_metadata?.full_name || "User",
        username:
          user.user_metadata?.email?.split("@")[0] ||
          `user_${Math.floor(Math.random() * 10000)}`,
        referral_code: generateReferralCode(),
        referred_by: referredBy,
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
    if (selectedDate) {
      const tradeDate = new Date(trade.created_at)

      const selected = new Date(selectedDate + "T00:00:00")

      if (
        tradeDate.getFullYear() !== selected.getFullYear() ||
        tradeDate.getMonth() !== selected.getMonth() ||
        tradeDate.getDate() !== selected.getDate()
      ) {
        return false
      }
    }

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
              <div className="flex flex-nowrap overflow-x-auto gap-2 mb-6 items-center">

                {/* Win/Loss */}
                {/* 🔥 RESULT FILTER */}
<div className="flex items-center gap-2 shrink-0">

  {/* ALL BUTTON */}
  <button
    onClick={() => setResultFilter("all")}
    className={`px-3 py-1.5 text-sm rounded whitespace-nowrap ${
      resultFilter === "all"
        ? "bg-emerald-500"
        : "bg-white/10 hover:bg-white/20"
    }`}
  >
    All
  </button>

  {/* TOGGLE */}
  <div className="flex items-center gap-2">

  <span
    className={`text-sm font-semibold ${
      resultFilter === "wins"
        ? "text-green-400"
        : "text-gray-400"
    }`}
  >
    W
  </span>

  <div
    onClick={() => {
      if (resultFilter === "all") {
        setResultFilter("wins")
      } else {
        setResultFilter(resultFilter === "wins" ? "losses" : "wins")
      }
    }}
    className={`relative w-28 h-8 flex items-center rounded-full px-2 cursor-pointer transition
      ${resultFilter === "wins" ? "bg-emerald-500" : ""}
      ${resultFilter === "losses" ? "bg-red-500" : ""}
      ${resultFilter === "all" ? "bg-white/10" : ""}
    `}
  >

    <div
      className={`bg-white w-6 h-6 rounded-full shadow-md transform transition ${
        resultFilter === "wins"
          ? "translate-x-0"
          : resultFilter === "losses"
          ? "translate-x-[4.5rem]"
          : "translate-x-9"
      }`}
    />

  </div>

  <span
    className={`text-sm font-semibold ${
      resultFilter === "losses"
        ? "text-red-400"
        : "text-gray-400"
    }`}
  >
    L
  </span>

</div>

</div>

                {/* Account */}
                <select
                  value={accountFilter}
                  onChange={(e) => setAccountFilter(e.target.value)}
                  className="bg-white text-black px-2 py-1.5 text-sm rounded shrink-0"
                >
                  <option value="all">All Accounts</option>
                  {accounts.map((acc) => (
                    <option key={acc}>{acc}</option>
                  ))}
                </select>

                {/* Timeframe */}
                {["All", "Daily", "Weekly", "Monthly"].map((t) => (
                  <button
                    key={t}
                    onClick={() => setTimeframe(t)}
                    className={`px-3 py-1.5 text-sm rounded whitespace-nowrap shrink-0 ${
                      timeframe === t
                        ? "bg-emerald-500"
                        : "bg-white/10 hover:bg-white/20"
                    }`}
                  >
                    {t}
                  </button>
                ))}

                <div className="relative shrink-0">
                  <input
                    type="date"
                    value={selectedDate}
                    onChange={(e) => setSelectedDate(e.target.value)}
                    className="bg-white text-black px-3 py-1.5 pr-8 text-sm rounded"
                  />

                  {selectedDate && (
                    <button
                      type="button"
                      onClick={() => setSelectedDate("")}
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-700 hover:text-red-500 transition"
                      aria-label="Clear date"
                    >
                      🗑
                    </button>
                  )}
                </div>

                {/* Advanced */}
                <button
                  onClick={() => setShowAdvanced(!showAdvanced)}
                  className="px-3 py-1.5 text-sm rounded whitespace-nowrap shrink-0 bg-blue-500 hover:bg-blue-600"
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
                    className="relative bg-white/5 border border-white/10 backdrop-blur-md p-7 rounded-xl shadow hover:scale-[1.01] transition"
                  >

                    <button
                      onClick={() => deleteTrade(trade.id)}
                      className="absolute top-3 right-3 text-white hover:text-red-400 text-xl transition"
                      type="button"
                    >
                      🗑
                    </button>

                    <div className="flex flex-col md:flex-row gap-6">
                      <div className="flex-1">
                        <div className="space-y-1 text-base text-gray-200">

                          <p className="text-lg font-semibold">
                            {trade.ticker} • {trade.direction}
                          </p>

                          <p className={`text-lg font-semibold ${trade.pnl >= 0 ? "text-green-400" : "text-red-400"}`}>
                            {formatCurrency(trade.pnl)}
                          </p>

                          <p className="text-sm">
                            <span className="text-gray-400">RR:</span> {formatNumber(trade.rr)}
                          </p>
                          <p className="text-sm">
                            <span className="text-gray-400">Points:</span> {formatNumber(trade.points)}
                          </p>
                          <p className="text-sm">
                            <span className="text-gray-400">Contracts:</span> {trade.contracts != null ? formatNumber(Number(trade.contracts)) : "-"}
                          </p>
                          <p className="text-sm">
                            <span className="text-gray-400">Session:</span> {trade.session}
                          </p>

                          <p className="text-sm">
                            <span className="text-gray-400">Account:</span>{" "}
                            {trade.account_type
                              ? `${trade.account_type} (${trade.account_id})`
                              : "-"}
                          </p>

                          <p className="text-sm">
                            <span className="text-gray-400">Notes:</span> {trade.notes || "-"}
                          </p>

                          {showAdvanced && (
                            <div className="mt-3 text-sm text-gray-300 space-y-1 border-t border-white/10 pt-3">
                              <p className="text-sm">
                                <span className="text-gray-400">Entry:</span> {formatCurrency(trade.entry_price)}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Exit:</span> {formatCurrency(trade.exit_price)}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Entry Time:</span> {trade.entry_time || "-"}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Exit Time:</span> {trade.exit_time || "-"}
                              </p>
                            </div>
                          )}

                        </div>
                      </div>

                      {(
                        (trade.confidence != null && trade.confidence !== "") ||
                        (trade.emotion != null && String(trade.emotion).trim() !== "") ||
                        trade.followed_plan != null ||
                        (trade.mistake_type != null && String(trade.mistake_type).trim() !== "") ||
                        (trade.market_condition != null && String(trade.market_condition).trim() !== "") ||
                        (trade.timeframe != null && String(trade.timeframe).trim() !== "") ||
                        trade.news_event != null ||
                        (trade.trade_type != null && String(trade.trade_type).trim() !== "") ||
                        (trade.psychology_notes != null && String(trade.psychology_notes).trim() !== "")
                      ) && (
                        <div className="md:w-[250px] border-t md:border-t-0 md:border-l border-white/10 pt-3 md:pt-0 md:pl-4 shrink-0 space-y-1">
                          <p className="text-sm text-gray-400 mb-2">Psychology</p>
                          {trade.confidence != null && trade.confidence !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Confidence:</span> {trade.confidence}
                            </p>
                          )}
                          {trade.emotion != null && String(trade.emotion).trim() !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Emotion:</span> {trade.emotion}
                            </p>
                          )}
                          {trade.followed_plan != null && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Followed Plan:</span> {trade.followed_plan ? "Yes" : "No"}
                            </p>
                          )}
                          {trade.mistake_type != null && String(trade.mistake_type).trim() !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Mistake:</span> {trade.mistake_type}
                            </p>
                          )}
                          {trade.market_condition != null && String(trade.market_condition).trim() !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Market:</span> {trade.market_condition}
                            </p>
                          )}
                          {trade.timeframe != null && String(trade.timeframe).trim() !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Timeframe:</span> {trade.timeframe}
                            </p>
                          )}
                          {trade.news_event != null && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">News:</span> {trade.news_event ? "Yes" : "No"}
                            </p>
                          )}
                          {trade.trade_type != null && String(trade.trade_type).trim() !== "" && (
                            <p className="text-sm text-gray-300">
                              <span className="text-gray-400">Type:</span> {trade.trade_type}
                            </p>
                          )}
                          {trade.psychology_notes != null && String(trade.psychology_notes).trim() !== "" && (
                            <p className="text-sm text-gray-300 mt-2">
                              <span className="text-gray-400">Psych Notes:</span>{" "}
                              {trade.psychology_notes}
                            </p>
                          )}
                        </div>
                      )}
                    </div>

                    {trade.image_url && (
                      <img
                        src={
  trade.image_url.startsWith("http")
    ? trade.image_url
    : `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`
}
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