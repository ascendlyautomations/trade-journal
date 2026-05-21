"use client"

import Navbar from "../components/Navbar"
import TradeFilterBar from "../components/TradeFilterBar"
import ProfileOnboarding, {
  ONBOARDING_FLAG,
  profileNeedsUsername,
} from "../components/ProfileOnboarding"
import InputTradeForm from "../components/InputTradeForm"
import PerformanceShareModal from "../components/PerformanceShareModal"
import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { useEffect, useMemo, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"
import {
  formatTradeClockTime,
  formatTradePrice,
  getTradeDurationDisplay,
} from "@/lib/tradeDisplayFormat"
import { formatDateOnly, formatTimeOnly } from "@/lib/formatDate"
import { formatEST } from "@/lib/formatEST"
import ShareTradeButton from "@/app/components/ShareTradeButton"
import ShareToConversationsModal from "@/app/components/ShareToConversationsModal"
import PostSetupImportModal from "../components/PostSetupImportModal"

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

function getDuration(
  start: string | null | undefined,
  end: string | null | undefined
) {
  if (!start || !end) return null

  const diff = +new Date(String(end)) - +new Date(String(start))
  if (!Number.isFinite(diff) || diff <= 0) return null

  const totalSeconds = Math.floor(diff / 1000)

  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  // under 1 minute → force 0m
  if (hours === 0 && minutes === 0) {
    return "0m"
  }

  if (hours === 0) {
    return seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`
  }

  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`
}

export default function TradesPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [resultFilter, setResultFilter] = useState<"all" | "wins" | "losses">("all")
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [timeframe, setTimeframe] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [loading, setLoading] = useState(true)
  const [selectedDate, setSelectedDate] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [authUserId, setAuthUserId] = useState<string | null>(null)
  const [gateProfile, setGateProfile] = useState<any | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [showImportModal, setShowImportModal] = useState(false)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [selectedTrade, setSelectedTrade] = useState<any>(null)
  const [isSendModalOpen, setIsSendModalOpen] = useState(false)
  const [visibleCount, setVisibleCount] = useState(10)
  /** Account rows for id → account_number (trades query unchanged; separate fetch) */
  const [accountRows, setAccountRows] = useState<any[]>([])
  const router = useRouter()

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  useEffect(() => {
    initPage()
  }, [])

  useEffect(() => {
    setVisibleCount(10)
  }, [timeframe, accountFilter, accountTypeFilter, resultFilter])

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

    const { data: accountsData } = await supabase
      .from("accounts")
      .select("id, account_number, name, account_size, mode, category")
      .eq("user_id", user.id)
    setAccountRows(accountsData || [])

    await fetchTrades(user.id)
  }

  async function fetchTrades(userId: string) {
    const { data: trades } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    console.log("FETCHED TRADES:", trades)

    setTrades(trades || [])
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

    if (timeframe === "yearly") {
      return tradeDate.getFullYear() === now.getFullYear()
    }

    if (timeframe === "custom") {
      if (!customRangeStart?.trim() || !customRangeEnd?.trim()) return true
      const start = new Date(customRangeStart + "T00:00:00")
      const end = new Date(customRangeEnd + "T23:59:59.999")
      return tradeDate >= start && tradeDate <= end
    }

    return true
  }

  function handleTimeframeChange(value: string) {
    setTimeframe(value)
    if (value !== "custom") {
      setCustomRangeStart("")
      setCustomRangeEnd("")
    }
  }

  function handleCustomRangeApply(start: string, end: string) {
    setSelectedDate("")
    setCustomRangeStart(start)
    setCustomRangeEnd(end)
    setTimeframe("custom")
  }

  const accountFilterMap = new Map<
    string,
    { value: string; label: string; accountType?: string | null }
  >()
  trades
    .filter((t) => t.account_name && t.account_size && t.account_id)
    .forEach((t) => {
      const accountName = String(t.account_name || "").trim()
      const size = String(t.account_size || "").trim()
      const id = String(t.account_id || "").trim()
      const value = `${accountName}|${size}|${id}`
      const accRow = accountById[id]
      const num = accRow?.account_number
      const label = [accountName, size, num ? `• #${num}` : ""]
        .filter((x) => x !== "")
        .join(" ")
        .replace(/\s+/g, " ")
        .trim()
      if (!accountFilterMap.has(value)) {
        accountFilterMap.set(value, {
          value,
          label,
          accountType: t.mode ?? t.account_type,
        })
      }
    })
  const accounts = Array.from(accountFilterMap.values())
  console.log("Accounts:", accounts)

  const tradesForPerformanceSharePool = useMemo(
    () =>
      filterTradesForPerformanceSharePool(trades, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        resultFilter,
      }),
    [trades, selectedDate, accountFilter, accountTypeFilter, resultFilter]
  )

  const filteredTrades = useMemo(() => {
    return tradesForPerformanceSharePool.filter((trade) => {
      if (!filterByTime(trade)) return false
      return true
    })
  }, [tradesForPerformanceSharePool, timeframe, customRangeStart, customRangeEnd])

  const visibleTrades = showPublicOnly
    ? filteredTrades.filter((t) => t.is_public === true)
    : filteredTrades

  const totalTrades = trades.length
  const wins = trades.filter((t) => t.pnl > 0)
  const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
  const totalPnL = trades.reduce((sum, t) => sum + (t.pnl || 0), 0)
  const avgRR =
    trades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
    (trades.length || 1)

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
          suppressPostSaveRedirect
          onComplete={(patch) => {
            setGateProfile((p: any) => (p ? { ...p, ...patch } : p))
            setShowOnboarding(false)
            setShowImportModal(true)
          }}
        />
      ) : null}

      <PostSetupImportModal
        open={showImportModal}
        onComplete={async () => {
          setShowImportModal(false)
          if (authUserId) {
            router.push(`/profile/${authUserId}`)
            router.refresh()
          }
        }}
      />

      <div className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10">

        <div className="relative z-50 w-full px-1 md:px-6 md:max-w-[1600px] md:mx-auto">

          {loading ? (
            <p className="text-center text-gray-400">Loading...</p>
          ) : (
            <>
              <div className="w-full px-2 md:px-4 mt-2.5 mb-1.5">
                <TradeFilterBar
                  variant="trades"
                  fullWidth
                  accounts={accounts}
                  accountFilter={accountFilter}
                  onAccountChange={setAccountFilter}
                  accountTypeFilter={accountTypeFilter}
                  onAccountTypeChange={setAccountTypeFilter}
                  timeframe={timeframe}
                  onTimeframeChange={handleTimeframeChange}
                  customRangeStart={customRangeStart}
                  customRangeEnd={customRangeEnd}
                  onCustomRangeApply={handleCustomRangeApply}
                  selectedDate={selectedDate}
                  onSelectedDateChange={setSelectedDate}
                  leading={
                  <div className="flex w-full shrink-0 flex-wrap items-center justify-center gap-2 md:w-auto md:flex-nowrap">
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
                  <div className="flex items-center gap-2 w-full md:w-auto">
                    <button
                      type="button"
                      onClick={() => setShowAdvanced(!showAdvanced)}
                      className="order-1 flex-1 h-10 px-3 rounded bg-white/10 hover:bg-white/20 text-sm text-white flex items-center justify-center md:order-3 md:h-auto md:flex-none md:rounded-md md:px-3 md:py-1.5"
                    >
                      {showAdvanced ? "Hide Advanced" : "Show Advanced"}
                    </button>
                    <button
                      onClick={() => setShowPublicOnly((prev) => !prev)}
                      className={`order-2 flex-[0.8] h-10 px-2 rounded text-sm font-medium transition flex items-center justify-center md:order-1 md:h-auto md:flex-none md:rounded-xl md:px-4 md:py-2
                        ${showPublicOnly
                          ? "bg-blue-500 text-white"
                          : "bg-white/10 text-gray-300 hover:bg-white/20"
                        }`}
                    >
                      Public
                    </button>
                    <button
                      type="button"
                      onClick={() => setShowPerformanceShare(true)}
                      className="order-3 h-10 w-10 rounded bg-white/10 hover:bg-white/20 flex items-center justify-center md:order-2 md:h-[34px] md:w-auto md:rounded-md md:px-3 md:py-1 md:text-sm md:text-white"
                      title="Share performance"
                      aria-label="Share performance"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        className="h-4 w-4 text-blue-300"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M4 12v7a1 1 0 001 1h14a1 1 0 001-1v-7M16 6l-4-4m0 0L8 6m4-4v12"
                        />
                      </svg>
                    </button>
                  </div>
                  }
                />
              </div>

              <p className="mb-1 mt-1 text-xs text-gray-400 px-2 md:px-0 md:mt-0">
                All-time stats
              </p>

              {/* 🔥 STATS BAR */}
              <div className="w-full grid grid-cols-2 md:grid-cols-4 gap-2 mb-3 px-1 mt-0 md:px-0">

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
              <div className="w-full grid grid-cols-1 md:grid-cols-2 gap-4">

                {visibleTrades.slice(0, visibleCount).map((trade) => {
  const entryPrice = trade.entry_price ?? trade.entry ?? null
  const exitPrice = trade.exit_price ?? trade.exit ?? null
  const entryRaw = trade.entry_time
  const exitRaw = trade.exit_time
  const entry = entryRaw ? formatTimeOnly(entryRaw) : null
  const exit = exitRaw ? formatTimeOnly(exitRaw) : null
  const duration = getDuration(entryRaw, exitRaw)
  const durationDisplay = getTradeDurationDisplay(
    trade.duration_text,
    trade.duration_seconds
  )
  const showDuration = durationDisplay !== null

  const acctLower = String(trade.mode ?? trade.account_type ?? "").toLowerCase().trim()
  const acc = accountById[String(trade.account_id ?? "")]
  const hasAccountLine =
    !!(String(trade.account_name || "").trim() ||
      String(trade.account_size || "").trim() ||
      acc?.account_number)

  if (process.env.NODE_ENV !== "production" && showAdvanced) {
    console.debug("[trades-page-duration-ui]", {
      tradeId: trade?.id ?? null,
      imported: String(trade?.account_type ?? "").toLowerCase() === "imported",
      durationText: trade?.duration_text ?? null,
      durationSeconds: trade?.duration_seconds ?? null,
      omittedFromUi: !showDuration,
    })
  }

  return (
    <div
      key={trade.id}
      className="relative w-full bg-white/5 border border-white/10 backdrop-blur-md px-2 py-3 md:px-4 rounded-xl shadow hover:scale-[1.02] hover:border-white/20 transition-all duration-200"
    >

                    <div className="absolute top-3 right-3 flex items-center gap-1">
                      <button
                        onClick={() => setEditingTrade({ ...trade })}
                        className="flex items-center justify-center rounded-md bg-white/10 px-3 py-1 text-sm text-white transition hover:bg-white/20"
                        type="button"
                      >
                        Edit
                      </button>
                      <ShareTradeButton
                        trade={trade}
                        variant="icon"
                        profile={gateProfile}
                        className="flex items-center justify-center rounded-md bg-white/10 px-3 py-1.5 text-sm text-white transition hover:bg-white/20"
                        onSendClick={() => {
                          setSelectedTrade(trade)
                          setIsSendModalOpen(true)
                        }}
                      />
                      <button
                        onClick={() => deleteTrade(trade.id)}
                        className="text-white hover:text-red-400 text-xl transition leading-none"
                        type="button"
                        aria-label="Delete trade"
                      >
                        🗑
                      </button>
                    </div>

                    <div className="flex flex-col md:flex-row gap-2.5">
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
                            {trade.is_public ? (
                              <span className="text-xs font-normal text-green-400 ml-2">
                                Public
                              </span>
                            ) : null}
                          </h2>

                          <p className="text-xs text-gray-400">
                            {formatDateOnly(
                              trade.entry_time || trade.created_at || undefined
                            )}
                            {entry ? ` • ${entry}` : ""}
                            {exit ? ` – ${exit}` : ""}
                            {duration ? ` (${duration})` : ""}
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

                            {hasAccountLine ? (
                              <div className="flex items-center gap-2 text-sm text-gray-300">
                                <span>
                                  {trade.account_name} {trade.account_size}
                                </span>
                                {acc?.account_number ? (
                                  <span className="opacity-70">
                                    • #{acc.account_number}
                                  </span>
                                ) : null}
                              </div>
                            ) : null}

                            {!trade.account_type && !hasAccountLine && (
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
                                {formatTradePrice(entryPrice)}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Exit:</span>{" "}
                                {formatTradePrice(exitPrice)}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Entry Time:</span>{" "}
                                {formatTradeClockTime(trade.entry_time, {
                                  sameDayAs: trade.created_at,
                                })}
                              </p>
                              <p className="text-sm">
                                <span className="text-gray-400">Exit Time:</span>{" "}
                                {formatTradeClockTime(trade.exit_time, {
                                  sameDayAs: trade.created_at,
                                })}
                              </p>
                              {showDuration ? (
                                <p className="text-sm">
                                  <span className="text-gray-400">Duration:</span>{" "}
                                  {durationDisplay}
                                </p>
                              ) : null}
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
                        alt=""
                        loading="lazy"
                        decoding="async"
                        className="w-full mt-4 rounded-lg border border-white/10 cursor-pointer"
                        onClick={() =>
                          setSelectedImage(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`)
                        }
                      />
                    )}

                    {trade.created_at && (
                      <p className="text-xs text-gray-400 mt-3">
                        {formatEST(trade.created_at)}
                      </p>
                    )}

                  </div>
                  );
                })}

              </div>

              {visibleCount < visibleTrades.length && (
                <div className="flex justify-center mt-4">
                  <button
                    type="button"
                    onClick={() => setVisibleCount((prev) => prev + 10)}
                    className="px-4 py-2 rounded-lg bg-blue-500 hover:bg-blue-600 transition"
                  >
                    Load More
                  </button>
                </div>
              )}
            </>
          )}

          {selectedImage && (
            <div
              className="fixed inset-0 bg-black bg-opacity-80 flex items-center justify-center"
              onClick={() => setSelectedImage(null)}
            >
              <img
                src={selectedImage}
                alt=""
                loading="lazy"
                decoding="async"
                className="max-w-[90%] max-h-[90%] rounded-lg"
              />
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

      <PerformanceShareModal
        open={showPerformanceShare}
        onClose={() => setShowPerformanceShare(false)}
        tradePool={tradesForPerformanceSharePool}
        subtitle="Matches account, mode & date filters"
        profile={gateProfile}
      />

      {isSendModalOpen && selectedTrade && (
        <ShareToConversationsModal
          open={isSendModalOpen}
          onClose={() => setIsSendModalOpen(false)}
          title="Send trade"
          tradeId={
            selectedTrade?.id != null ? String(selectedTrade.id) : null
          }
        />
      )}

    </>
  )
}

function Stat({ title, value, positive }: any) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="bg-white/5 border border-white/10 p-4 p-3 md:p-5 rounded-xl text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}