"use client"

import Navbar from "../components/Navbar"
import TradeFilterBar from "../components/TradeFilterBar"
import ProfileOnboarding, {
  ONBOARDING_FLAG,
  profileNeedsUsername,
} from "../components/ProfileOnboarding"
import InputTradeForm from "../components/InputTradeForm"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

function formatMoney(value: unknown): string {
  if (value === null || value === undefined) return "-"
  const number = Number(value)
  if (Number.isNaN(number)) return "-"
  return number < 0
    ? `-$${Math.abs(number).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${number.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function formatNumber(value: unknown): string {
  if (value === null || value === undefined) return "-"
  const number = Number(value)
  if (Number.isNaN(number)) return "-"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

export default function TradesPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [resultFilter, setResultFilter] = useState<"all" | "wins" | "losses">("all")
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [timeframe, setTimeframe] = useState("all")
  const [loading, setLoading] = useState(true)
  const [selectedDate, setSelectedDate] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [authUserId, setAuthUserId] = useState<string | null>(null)
  const [gateProfile, setGateProfile] = useState<any | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)

  const router = useRouter()

  useEffect(() => {
    initPage()
  }, [])

  useEffect(() => {
    if (loading || !gateProfile) return
    let fromSignup = false
    try {
      fromSignup = sessionStorage.getItem(ONBOARDING_FLAG) === "1"
    } catch {
      /* ignore */
    }
    if (fromSignup || profileNeedsUsername(gateProfile.username)) {
      setShowOnboarding(true)
    }
  }, [loading, gateProfile])

  async function initPage() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) {
      router.push("/login")
      return
    }

    setAuthUserId(user.id)

    // 🔥 CREATE PROFILE IF NEEDED (GOOGLE FIX)
    const { data: existingProfile } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)

    if (!existingProfile || existingProfile.length === 0) {
      const referralCode =
        typeof window !== "undefined"
          ? localStorage.getItem("referral_code")
          : null

      console.log("🔥 REFERRAL ON SIGNUP:", referralCode)

      function generateReferralCode() {
        return Math.random().toString(36).substring(2, 8).toUpperCase()
      }

      const { error: profileUpsertErr } = await supabase
        .from("profiles")
        .upsert(
          {
            id: user.id,
            username:
              user.user_metadata?.email?.split("@")[0] ||
              user.email ||
              `user_${user.id.slice(0, 6)}`,
            name: user.user_metadata?.full_name || "",
            is_pro: false,
            subscription_status: "inactive",
            created_at: new Date().toISOString(),
            referral_code: generateReferralCode(),
            referred_by: referralCode || null,
          },
          { onConflict: "id", ignoreDuplicates: true }
        )

      if (profileUpsertErr) {
        console.error(
          "ERROR:",
          JSON.stringify(profileUpsertErr, null, 2)
        )
      }
    }

    const { data: profRow } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .maybeSingle()

    setGateProfile(profRow ?? null)

    await fetchTrades(user.id)
  }

  async function fetchTrades(userId: string) {
    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", userId)
      .neq("mode", "backtest")
      .order("created_at", { ascending: false })

    console.log("FETCHED TRADES:", data)

    setTrades(data || [])
    setLoading(false)
  }

  async function deleteTrade(id: string) {
    if (!confirm("Delete this trade?")) return
    await supabase.from("trades").delete().eq("id", id)
    setTrades(prev => prev.filter(t => t.id !== id))
  }

  async function handleTradeFormSaved() {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) await fetchTrades(user.id)
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

  const accountMap = new Map<
    string,
    { value: string; label: string; accountType?: string | null }
  >()
  trades
    .filter(t => t.account_name && t.account_size && t.account_id)
    .forEach((t) => {
      const accountName = String(t.account_name || "").trim()
      const size = String(t.account_size || "").trim()
      const id = String(t.account_id || "").trim()
      const value = `${accountName}|${size}|${id}`
      const label = `${accountName} ${size} #${id}`
        .trim()
        .replace(/\s+/g, " ")
      if (!accountMap.has(value)) {
        accountMap.set(value, {
          value,
          label,
          accountType: t.mode ?? t.account_type,
        })
      }
    })
  const accounts = Array.from(accountMap.values())
  console.log("Accounts:", accounts)

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
    const accountName = String(trade.account_name || "").trim()
    const size = String(trade.account_size || "").trim()
    const id = String(trade.account_id || "").trim()
    const accountKey = `${accountName}|${size}|${id}`
    if (accountKey !== accountFilter) return false
  }

  const tradeMode = String(trade.mode ?? trade.account_type ?? "")
    .toLowerCase()
    .trim()
  const selectedAcct = accountTypeFilter.toLowerCase().trim()
  if (accountTypeFilter !== "all") {
    console.log("Filtering:", trade.mode ?? trade.account_type, accountTypeFilter)
    if (tradeMode !== selectedAcct) {
      return false
    }
  }

  // 🔥 THIS STAYS LAST
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

      {showOnboarding && authUserId && gateProfile ? (
        <ProfileOnboarding
          userId={authUserId}
          initialUsername={gateProfile.username}
          initialBio={gateProfile.bio}
          initialTradingStyle={gateProfile.trading_style}
          initialStartedTrading={gateProfile.started_trading}
          initialAvatarUrl={gateProfile.avatar_url}
          onComplete={(patch) => {
            setGateProfile((p: any) => (p ? { ...p, ...patch } : p))
            setShowOnboarding(false)
          }}
        />
      ) : null}

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">

        <div className="p-12 max-w-7xl mx-auto">

          <h1 className="text-3xl font-semibold mb-5 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Trade History
          </h1>

          {loading ? (
            <p className="text-center text-gray-400">Loading...</p>
          ) : (
            <>
              <TradeFilterBar
                className="mb-5"
                accounts={accounts}
                accountFilter={accountFilter}
                onAccountChange={setAccountFilter}
                accountTypeFilter={accountTypeFilter}
                onAccountTypeChange={setAccountTypeFilter}
                timeframe={timeframe}
                onTimeframeChange={setTimeframe}
                selectedDate={selectedDate}
                onSelectedDateChange={setSelectedDate}
                leading={
                  <div className="flex shrink-0 items-center gap-2">
                    <button
                      type="button"
                      onClick={() => setResultFilter("all")}
                      className={`whitespace-nowrap rounded-md px-3 py-1 text-sm text-white ${
                        resultFilter === "all"
                          ? "bg-emerald-500 hover:bg-emerald-600"
                          : "bg-white/10 hover:bg-white/20"
                      }`}
                    >
                      All
                    </button>

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
                        role="button"
                        tabIndex={0}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault()
                            if (resultFilter === "all") {
                              setResultFilter("wins")
                            } else {
                              setResultFilter(
                                resultFilter === "wins" ? "losses" : "wins"
                              )
                            }
                          }
                        }}
                        onClick={() => {
                          if (resultFilter === "all") {
                            setResultFilter("wins")
                          } else {
                            setResultFilter(
                              resultFilter === "wins" ? "losses" : "wins"
                            )
                          }
                        }}
                        className={`relative flex h-8 w-28 cursor-pointer items-center rounded-full px-2 transition
                          ${resultFilter === "wins" ? "bg-emerald-500" : ""}
                          ${resultFilter === "losses" ? "bg-red-500" : ""}
                          ${resultFilter === "all" ? "bg-white/10" : ""}
                        `}
                      >
                        <div
                          className={`h-6 w-6 transform rounded-full bg-white shadow-md transition ${
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
                }
                trailing={
                  <button
                    type="button"
                    onClick={() => setShowAdvanced(!showAdvanced)}
                    className="shrink-0 whitespace-nowrap rounded-md bg-white/10 px-3 py-1 text-sm text-white hover:bg-white/20"
                  >
                    {showAdvanced ? "Hide Advanced" : "Show Advanced"}
                  </button>
                }
              />

              {/* 🔥 STATS BAR */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10">

                <Stat
                  title="Trades"
                  value={totalTrades.toLocaleString(undefined, {
                    maximumFractionDigits: 0,
                  })}
                />
                <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />

                <Stat
                  title="P&L"
                  value={formatMoney(totalPnL)}
                  positive={totalPnL >= 0}
                />

                <Stat title="Avg RR" value={formatNumber(avgRR)} />

              </div>

              {/* GRID */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">

                {filteredTrades.map((trade) => {
  const entry = trade.entry_price ?? trade.entry ?? null
  const exit = trade.exit_price ?? trade.exit ?? null

  const acctLower = String(trade.mode ?? trade.account_type ?? "").toLowerCase().trim()
  const accountLabel = `${String(trade.account_name || "").trim()} ${String(
    trade.account_size || ""
  ).trim()} ${trade.account_id ? `#${String(trade.account_id).trim()}` : ""}`
    .replace(/\s+/g, " ")
    .trim()

  return (
    <div
      key={trade.id}
      className="relative bg-white/5 border border-white/10 backdrop-blur-md p-7 rounded-xl shadow hover:scale-[1.02] hover:border-white/20 transition-all duration-200"
    >

                    <div className="absolute top-3 right-3 flex items-center gap-2">
                      <button
                        onClick={() => setEditingTrade({ ...trade })}
                        className="text-sm px-2 py-1 rounded bg-white/10 hover:bg-white/20 text-white transition"
                        type="button"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => deleteTrade(trade.id)}
                        className="text-white hover:text-red-400 text-xl transition leading-none"
                        type="button"
                        aria-label="Delete trade"
                      >
                        🗑
                      </button>
                    </div>

                    <div className="flex flex-col md:flex-row gap-6">
                      <div className="flex-1">
                        <div className="space-y-1 text-base text-gray-200">

                          <h2 className="text-lg font-semibold flex items-center gap-2 flex-wrap">
                            {trade.ticker} •{" "}
                            {trade.direction || (
                              trade.exit_price && trade.entry_price
                                ? trade.exit_price > trade.entry_price
                                  ? "Long"
                                  : "Short"
                                : "Unknown"
                            )}
                          </h2>

                          <p className="text-xs text-gray-400">
                            {new Date(trade.created_at).toLocaleDateString()}
                          </p>

                          <div
                            className={`inline-block px-3 py-1 rounded-lg text-lg font-bold mt-1 ${
                              (Number(trade.pnl) || 0) >= 0
                                ? "bg-green-500/20 text-green-400"
                                : "bg-red-500/20 text-red-400"
                            }`}
                          >
                            {formatMoney(trade.pnl)}
                          </div>

                          <div className="flex gap-2 mt-2 flex-wrap">
                            <span className="bg-white/10 px-2 py-1 rounded text-xs">
                              RR: {formatNumber(trade.rr)}
                            </span>

                            <span className="bg-white/10 px-2 py-1 rounded text-xs">
                              Pts: {formatNumber(trade.points)}
                            </span>
                          </div>
                          <p className="text-sm">
                            <span className="text-gray-400">Contracts:</span>{" "}
                            {trade.contracts != null
                              ? Number(trade.contracts).toLocaleString()
                              : "-"}
                          </p>
                          <p className="text-sm">
                            <span className="text-gray-400">Session:</span> {trade.session}
                          </p>

                          <div className="mt-1 flex flex-wrap items-center gap-2">
                            {trade.mode !== "backtest" && trade.account_type && (
                              <span
                                className={`px-2 py-0.5 text-xs rounded-full font-medium ${
                                  acctLower === "funded"
                                    ? "bg-green-500/20 text-green-400"
                                    : acctLower === "eval"
                                      ? "bg-yellow-500/20 text-yellow-400"
                                      : acctLower === "live"
                                        ? "bg-blue-500/20 text-blue-400"
                                        : acctLower === "backtest"
                                          ? "bg-indigo-500/20 text-indigo-300"
                                        : "bg-gray-500/20 text-gray-400"
                                }`}
                              >
                                {trade.account_type}
                              </span>
                            )}

                            {acctLower === "backtest" && (
                              <span className="rounded bg-blue-500 px-2 py-1 text-xs text-white">
                                Backtest
                              </span>
                            )}

                            {accountLabel && (
                              <span className="text-sm text-gray-300">
                                {accountLabel}
                              </span>
                            )}

                            {!trade.account_type && !accountLabel && (
                              <span className="text-xs text-gray-500">—</span>
                            )}
                          </div>

                          {trade.public_description ? (
                            <div className="mt-2 px-0">
                              <p className="text-sm text-gray-300">
  <span className="text-gray-400">Public Description:</span>{" "}
  {trade.public_description}
</p>
                            </div>
                          ) : null}

                          {trade.strategy && (
                            <p className="text-xs text-gray-400">
                              Strategy: {trade.strategy}
                            </p>
                          )}

                          <p className="text-sm">
                            <span className="text-gray-400">Notes:</span> {trade.notes || "-"}
                          </p>

                          {showAdvanced && (
                            <div className="mt-3 text-sm text-gray-300 space-y-1 border-t border-white/10 pt-3">
                              <p className="text-sm">
                                <span className="text-gray-400">Entry:</span>{" "}
                                {formatNumber(entry)}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Exit:</span>{" "}
                                {formatNumber(exit)}
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
                  );
                })}

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

          {editingTrade && (
            <InputTradeForm
              existingTrade={editingTrade}
              onClose={() => setEditingTrade(null)}
              onSave={() => void handleTradeFormSaved()}
            />
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