"use client"
import Link from "next/link"
import Navbar from "../components/Navbar"
import EmptyState from "../components/ui/EmptyState"
import { SkeletonCalendarPage } from "../components/ui/skeletons"
import TradesPageTradeCard from "../components/TradesPageTradeCard"
import TradesPageOverlays from "../components/TradesPageOverlays"
import { formatEST } from "@/lib/formatEST"
import {
  getTradingDayKey,
  resolveTradingTimeSourceForKey,
  toDateKey,
} from "@/lib/formatDate"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import { useEffect, useMemo, useState, useCallback } from "react"
import { supabase } from "../../lib/supabaseClient"
import { deleteUserTrade } from "@/lib/deleteTrade"
import { formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { ConfirmModal, useDeleteTradeConfirmation } from "../components/ui"
export default function CalendarPage() {
  useScrollPageTopOnMount()
  const [trades, setTrades] = useState<any[]>([])
  const [shareProfile, setShareProfile] = useState<{
    referral_code?: string | null
  } | null>(null)
  const [accountFilter, setAccountFilter] = useState("all")
  const [selectedMode, setSelectedMode] = useState("all")
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [selectedTrades, setSelectedTrades] = useState<any[]>([])
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)
  const [accountRows, setAccountRows] = useState<any[]>([])
  const [tradesLoaded, setTradesLoaded] = useState(false)

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) return

    const { data: profileRow } = await supabase
      .from("profiles")
      .select("referral_code")
      .eq("id", user.id)
      .maybeSingle()
    setShareProfile(profileRow ?? null)

    const [{ data }, { data: accountsData }] = await Promise.all([
      supabase.from("trades").select("*").eq("user_id", user.id),
      supabase
        .from("accounts")
        .select("id, account_number, name, account_size, mode, category, is_active")
        .eq("user_id", user.id),
    ])

    if (data) setTrades(data)
    setAccountRows(accountsData || [])
    setTradesLoaded(true)
  }

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  async function handleTradeFormSaved() {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return

    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", user.id)

    if (!data) return
    setTrades(data)

    if (selectedDate) {
      const list = data.filter((trade) => {
        const resolved = resolveTradingTimeSourceForKey(trade)
        if (!resolved) return false
        return getTradingDayKey(resolved) === selectedDate
      })
      setSelectedTrades(list)
    }
    setEditingTrade(null)
  }

  const performDeleteTrade = useCallback(async (id: string) => {
    await deleteUserTrade(supabase, id)
    setTrades((prev) => prev.filter((t) => String(t.id) !== id))
    setSelectedTrades((prev) => prev.filter((t) => String(t.id) !== id))
  }, [])

  const { requestDelete: handleDeleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  function formatPNL(value: number) {
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString()}`
  }

  function safeTradeCount(value: unknown) {
    const n = typeof value === "string" ? parseFloat(value) : Number(value)
    if (!Number.isFinite(n)) return 0
    return Math.max(0, Math.round(n))
  }

  const accountFilterOptions = useMemo(() => {
    const seen = new Set<string>()
    const opts: { value: string; label: string }[] = []
    for (const t of trades) {
      const id = t.account_id != null ? String(t.account_id) : ""
      if (!id || seen.has(id)) continue
      seen.add(id)
      const label = formatTradeAccountNameSizeLine(t, accountById[id])
      const prefix = t.account_type ? `${t.account_type} · ` : ""
      opts.push({
        value: id,
        label: `${prefix}${label || "Account"}`.trim(),
      })
    }
    return opts
  }, [trades, accountById])

  const filteredTrades = trades.filter((trade) => {
    if (accountFilter !== "all") {
      if (String(trade.account_id ?? "") !== accountFilter) {
        return false
      }
    }
    if (selectedMode === "all") return true
    const m = selectedMode.toLowerCase()
    return (
      trade.mode?.toLowerCase() === m ||
      trade.account_type?.toLowerCase() === m
    )
  })

  const year = currentDate.getFullYear()
  const month = currentDate.getMonth()

  const firstDayOfMonth = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()

  const dailyData: any = {}

  filteredTrades.forEach((trade) => {
    const resolved = resolveTradingTimeSourceForKey(trade)
    if (!resolved) return
    const tradeKey = getTradingDayKey(resolved)
    if (!tradeKey) return

    const [yk, mk, dk] = tradeKey.split("-").map(Number)
    if (yk !== year || mk !== month + 1) return

    const day = dk
    if (!dailyData[day]) dailyData[day] = { pnl: 0, trades: [] }
    dailyData[day].pnl += trade.pnl || 0
    dailyData[day].trades.push(trade)
  })

  const monthTrades = Object.values(dailyData).flatMap((d: any) => d.trades)

  const totalTrades = safeTradeCount(monthTrades.length)
  const wins = monthTrades.filter((t: any) => t.pnl > 0)
  const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
  const totalPnL = monthTrades.reduce((sum: number, t: any) => sum + (t.pnl || 0), 0)

  const calendarDays = []
  for (let i = 0; i < 42; i++) {
    const dayNumber = i - firstDayOfMonth + 1
    calendarDays.push(dayNumber > 0 && dayNumber <= daysInMonth ? dayNumber : null)
  }
  const weeks: Array<Array<number | null>> = []
  for (let i = 0; i < calendarDays.length; i += 7) {
    weeks.push(calendarDays.slice(i, i + 7))
  }

  const getWeekTotal = (weekDays: Array<number | null>) => {
    return weekDays.reduce((total, day) => {
      if (!day) return total
      const dayData = dailyData[day]
      const dayTotal = dayData?.trades?.reduce(
        (sum: number, t: any) => sum + (t.pnl || 0),
        0
      ) || 0
      return total + dayTotal
    }, 0)
  }

  function changeMonth(offset: number) {
    const newDate = new Date(currentDate)
    newDate.setMonth(newDate.getMonth() + offset)
    setCurrentDate(newDate)
    setSelectedDate(null)
    setSelectedTrades([])
  }

  function handleDaySelect(dayNum: number) {
    const key = toDateKey(year, month, dayNum)
    if (selectedDate === key) {
      setSelectedDate(null)
      setSelectedTrades([])
      return
    }
    setSelectedDate(key)
    const list = filteredTrades.filter((trade) => {
      const resolved = resolveTradingTimeSourceForKey(trade)
      if (!resolved) return false
      return getTradingDayKey(resolved) === key
    })
    setSelectedTrades(list)
  }

  const selectedDayStats = useMemo(() => {
    if (!selectedDate) return null
    const dayTrades = selectedTrades || []
    const totalTradesForDay = safeTradeCount(dayTrades.length)
    const totalPnlForDay = dayTrades.reduce(
      (sum: number, t: any) => sum + (Number(t.pnl) || 0),
      0
    )
    const winsForDay = dayTrades.filter((t: any) => (Number(t.pnl) || 0) > 0)
    const lossesForDay = dayTrades.filter((t: any) => (Number(t.pnl) || 0) < 0)
    const winRateForDay = totalTradesForDay
      ? (winsForDay.length / totalTradesForDay) * 100
      : 0
    const avgRRForDay = averageRrFromTrades(dayTrades)
    const bestTradeForDay = dayTrades.length
      ? Math.max(...dayTrades.map((t: any) => Number(t.pnl) || 0))
      : 0
    const worstTradeForDay = dayTrades.length
      ? Math.min(...dayTrades.map((t: any) => Number(t.pnl) || 0))
      : 0
    const avgWinForDay = winsForDay.length
      ? winsForDay.reduce((sum: number, t: any) => sum + (Number(t.pnl) || 0), 0) /
        winsForDay.length
      : 0
    const avgLossForDay = lossesForDay.length
      ? lossesForDay.reduce((sum: number, t: any) => sum + (Number(t.pnl) || 0), 0) /
        lossesForDay.length
      : 0
    const totalPointsForDay = dayTrades.reduce(
      (sum: number, t: any) => sum + (resolveTradePoints(t) ?? 0),
      0
    )
    const sessionCounts = dayTrades.reduce((acc: Record<string, number>, t: any) => {
      const session = String(t.session || "").trim()
      if (!session) return acc
      acc[session] = (acc[session] || 0) + 1
      return acc
    }, {})
    const modeCounts = dayTrades.reduce((acc: Record<string, number>, t: any) => {
      const mode = String(t.mode ?? t.account_type ?? "").trim()
      if (!mode) return acc
      acc[mode] = (acc[mode] || 0) + 1
      return acc
    }, {})
    const mainSession = Object.entries(sessionCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null
    const mainMode = Object.entries(modeCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null

    return {
      totalTradesForDay,
      totalPnlForDay,
      winRateForDay,
      avgRRForDay,
      winningTrades: safeTradeCount(winsForDay.length),
      losingTrades: safeTradeCount(lossesForDay.length),
      bestTradeForDay,
      worstTradeForDay,
      avgWinForDay,
      avgLossForDay,
      totalPointsForDay,
      mainSession,
      mainMode,
    }
  }, [selectedDate, selectedTrades])

  function renderCalendarDay(
    day: number | null,
    weekIndex: number,
    keySuffix: string
  ) {
    if (!day) {
      return (
        <div
          key={`empty-${weekIndex}-${keySuffix}`}
          className="relative aspect-square w-full min-h-0 rounded-lg border border-white/10 bg-white/[0.03]"
        />
      )
    }

    const data = dailyData[day]
    const dayKey = toDateKey(year, month, day)

    return (
      <div
        key={`day-${weekIndex}-${keySuffix}`}
        role="button"
        tabIndex={0}
        onClick={() => handleDaySelect(day)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault()
            handleDaySelect(day)
          }
        }}
        className={`
          relative z-10 aspect-square w-full min-h-0 cursor-pointer rounded-lg border
          flex flex-col items-center justify-center px-0.5 py-1 text-center text-xs md:text-sm
          transition md:hover:scale-[1.03]
          ${selectedDate === dayKey ? "ring-2 ring-blue-400 ring-inset" : ""}
          ${data?.pnl > 0 ? "border-emerald-400/50 bg-emerald-500/20 text-white" : ""}
          ${data?.pnl < 0 ? "border-red-400/50 bg-red-500/20 text-white" : ""}
          ${!data ? "border-white/15 bg-[#0b1220] text-gray-100" : ""}
        `}
      >
        <div className="flex w-full max-w-full flex-col items-center justify-center overflow-hidden leading-tight">
          <div className="w-full truncate text-center text-sm font-semibold leading-tight text-current">
            {day}
          </div>

          {data ? (
            <div className="mt-0.5 w-full truncate text-center text-[11px] leading-tight">
              <div
                className={`truncate text-center font-semibold leading-tight ${
                  data.pnl > 0
                    ? "text-emerald-100"
                    : data.pnl < 0
                      ? "text-red-100"
                      : "text-white"
                }`}
              >
                {formatPNL(data.pnl)}
              </div>
              <div className="truncate text-center text-[10px] leading-tight text-white/80">
                {safeTradeCount(data?.trades?.length)} trades
              </div>
            </div>
          ) : null}
        </div>
      </div>
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white py-6">

        <div className="max-w-7xl mx-auto w-full px-4">

          {!tradesLoaded ? (
            <SkeletonCalendarPage />
          ) : (
            <>
          {trades.length === 0 ? (
            <EmptyState
              title="No Trades Yet"
              description="Start tracking your performance by logging your first trade."
              action={
                <Link
                  href="/app"
                  className="text-sm font-medium text-blue-300 hover:text-blue-200"
                >
                  Add Trade →
                </Link>
              }
              className="mb-6 py-10"
            />
          ) : null}

          <div className="grid grid-cols-1 md:grid-cols-[2fr_1.4fr] gap-4 md:gap-8 items-start">

          {/* LEFT SIDE (CALENDAR) */}
          <div className="w-full min-w-0 overflow-x-hidden">

            {/* HEADER — arrows + month (same row mobile & desktop) */}
            <div className="flex items-center justify-between mb-3 md:mb-6">
              <button
                type="button"
                onClick={() => changeMonth(-1)}
                className="shrink-0 text-xl hover:text-blue-400"
              >
                &lt;
              </button>

              <h2 className="flex-1 text-center text-lg md:text-2xl font-semibold md:font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent px-2">
                {currentDate.toLocaleString("default", { month: "long" })} {year}
              </h2>

              <button
                type="button"
                onClick={() => changeMonth(1)}
                className="shrink-0 text-xl hover:text-blue-400"
              >
                &gt;
              </button>
            </div>

            <div className="flex items-center gap-3 flex-wrap w-full max-w-xl mx-auto mb-3 md:mb-4">
              <select
                value={accountFilter}
                onChange={(e) => {
                  setAccountFilter(e.target.value)
                  setSelectedDate(null)
                  setSelectedTrades([])
                }}
                className="flex-1 min-w-[140px] bg-[#0f172a] border border-white/10 px-3 py-2 rounded text-white"
              >
                <option value="all">All Accounts</option>
                {accountFilterOptions.map(({ value, label }) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
              <select
                value={selectedMode}
                onChange={(e) => {
                  setSelectedMode(e.target.value)
                  setSelectedDate(null)
                  setSelectedTrades([])
                }}
                className="flex-1 min-w-[140px] bg-[#0b1f3a] text-white border border-white/10 rounded-lg px-3 py-2"
              >
                <option value="all">All Modes</option>
                <option value="live">Live</option>
                <option value="funded">Funded</option>
                <option value="eval">Eval</option>
                <option value="backtest">Backtest</option>
              </select>
            </div>

            {/* WEEKDAY LABELS — Sun–Fri mobile, full week desktop */}
            <div className="grid min-w-0 grid-cols-6 gap-1 mb-2 text-center text-gray-400 text-xs md:hidden">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri"].map((d) => (
                <div key={d}>{d}</div>
              ))}
            </div>
            <div className="hidden md:grid min-w-0 grid-cols-7 gap-2 mb-2 text-center text-gray-400 text-sm">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((d) => (
                <div key={d}>{d}</div>
              ))}
            </div>

            {/* CALENDAR GRID */}
            <div className="space-y-2">
              {weeks.map((week, weekIndex) => {
                const weekTotal = Number(getWeekTotal(week) ?? 0)
                const mobileWeek = week.filter((day, dayIndex) => {
                  if (day === null) {
                    const weekday = (weekIndex * 7 + dayIndex) % 7
                    return weekday !== 6
                  }
                  const d = new Date(year, month, day).getDay()
                  return d !== 6
                })
                const hideMobileWeek = mobileWeek.every((d) => d === null)

                return (
                  <div key={weekIndex} className="mb-2">
                    <div
                      className={`grid min-w-0 grid-cols-6 gap-1 md:hidden ${hideMobileWeek ? "hidden" : ""}`}
                    >
                      {mobileWeek.map((day, i) =>
                        renderCalendarDay(day, weekIndex, `m-${i}`)
                      )}
                    </div>

                    <div className="hidden md:grid min-w-0 grid-cols-7 gap-2">
                      {week.map((day, i) =>
                        renderCalendarDay(day, weekIndex, `d-${i}`)
                      )}
                    </div>

                    <div className="relative z-0 w-full flex justify-center mt-1 md:mt-2 pointer-events-none">
                      <span
                        className={`rounded-full px-3 py-1 text-xs md:text-sm font-semibold ${
                          weekTotal >= 0
                            ? "bg-green-500/20 text-green-400"
                            : "bg-red-500/20 text-red-400"
                        }`}
                      >
                        Week: {formatPNL(weekTotal)}
                      </span>
                    </div>
                  </div>
                )
              })}
            </div>

          </div>

          {/* RIGHT SIDE PANEL — NOW ALIGNED TO TOP */}
          <div className="w-full min-w-0 max-w-none space-y-4 mt-4 md:mt-[52px]">

            {/* STATS */}
            <div className="bg-white/5 p-5 rounded-xl border border-white/10">
              {selectedDate && selectedDayStats ? (
                <>
                  <h3 className="text-blue-400 font-semibold mb-1">Selected Day Stats</h3>
                  <p className="text-xs text-gray-400 mb-3">
                    {formatEST(`${selectedDate}T12:00:00`)}
                  </p>

                  {selectedDayStats.totalTradesForDay === 0 ? (
                    <p className="text-sm text-gray-400">No trades for this day.</p>
                  ) : (
                    <div className="space-y-2 text-sm">
                      <p>
                        Total P&L:{" "}
                        <span
                          className={
                            selectedDayStats.totalPnlForDay > 0
                              ? "text-emerald-400"
                              : selectedDayStats.totalPnlForDay < 0
                                ? "text-red-400"
                                : ""
                          }
                        >
                          {formatPNL(selectedDayStats.totalPnlForDay)}
                        </span>
                      </p>
                      <p>Total Trades: {selectedDayStats.totalTradesForDay}</p>
                      <p>Win Rate: {selectedDayStats.winRateForDay.toFixed(1)}%</p>
                      <p>Avg RR: {formatRR(selectedDayStats.avgRRForDay)}</p>
                      <p>Winning Trades: {selectedDayStats.winningTrades}</p>
                      <p>Losing Trades: {selectedDayStats.losingTrades}</p>
                      <p className={selectedDayStats.bestTradeForDay >= 0 ? "text-emerald-400" : "text-red-400"}>
                        Best Trade: {formatPNL(selectedDayStats.bestTradeForDay)}
                      </p>
                      <p className={selectedDayStats.worstTradeForDay >= 0 ? "text-emerald-400" : "text-red-400"}>
                        Worst Trade: {formatPNL(selectedDayStats.worstTradeForDay)}
                      </p>
                      <p>Avg Win: {formatPNL(selectedDayStats.avgWinForDay)}</p>
                      <p>Total Points: {formatDecimal(selectedDayStats.totalPointsForDay, 2)}</p>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <h3 className="text-blue-400 font-semibold mb-3">Monthly Stats</h3>

                  <div className="space-y-2 text-sm">
                    <p>Total Trades: {totalTrades}</p>
                    <p>Win Rate: {winRate.toFixed(1)}%</p>
                    <p className={totalPnL > 0 ? "text-emerald-400" : totalPnL < 0 ? "text-red-400" : ""}>
                      Total P&L: {formatPNL(totalPnL)}
                    </p>
                  </div>
                </>
              )}
            </div>

            {selectedDate ? (
              <div className="mt-4">
                <h3 className="text-sm md:text-lg font-semibold mb-2 text-center">
                  Trades on {formatEST(`${selectedDate}T12:00:00`)}
                </h3>

                {selectedTrades.length === 0 ? (
                  <p className="text-center text-gray-400 text-sm">No trades this day</p>
                ) : (
                  <div className="flex w-full flex-col gap-3">
                    {selectedTrades.map((trade) => (
                      <div key={trade.id} className="w-full min-w-0">
                        <TradesPageTradeCard
                          trade={trade}
                          showAdvanced={false}
                          accountRow={accountById[String(trade.account_id ?? "")]}
                          shareProfile={shareProfile}
                          onEdit={(t) => setEditingTrade({ ...t })}
                          onDelete={handleDeleteTrade}
                          onSendClick={(t) => setSendTradeId(String(t.id))}
                          onImageClick={setSelectedImage}
                        />
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ) : null}

          </div>

          </div>
            </>
          )}

        </div>

      </div>
      <TradesPageOverlays
        selectedImage={selectedImage}
        editingTrade={editingTrade}
        showPerformanceShare={false}
        sendTradeId={sendTradeId}
        tradesForPerformanceSharePool={[]}
        gateProfile={null}
        onCloseImageLightbox={() => setSelectedImage(null)}
        onCloseEditForm={() => setEditingTrade(null)}
        onTradeFormSaved={() => void handleTradeFormSaved()}
        onClosePerformanceShare={() => {}}
        onCloseSendModal={() => setSendTradeId(null)}
      />
      <ConfirmModal {...confirmModalProps} />
    </>
  )
}