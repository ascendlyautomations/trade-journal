"use client"
import Navbar from "../components/Navbar"
import TradeCard from "../components/TradeCard"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

function toDateKey(y: number, mZeroBased: number, dayNum: number) {
  return `${y}-${String(mZeroBased + 1).padStart(2, "0")}-${String(dayNum).padStart(2, "0")}`
}

export default function CalendarPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [selectedTrades, setSelectedTrades] = useState<any[]>([])

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) return

    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", user.id)

    if (data) setTrades(data)
  }

  function formatPNL(value: number) {
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString()}`
  }

  const accounts = Array.from(
    new Set(
      trades
        .filter(t => t.account_type && t.account_id)
        .map(t => `${t.account_type} (${t.account_id})`)
    )
  )

  const filteredTrades = trades.filter((trade) => {
    if (accountFilter === "all") return true
    return `${trade.account_type} (${trade.account_id})` === accountFilter
  })

  const year = currentDate.getFullYear()
  const month = currentDate.getMonth()

  const firstDayOfMonth = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()

  const dailyData: any = {}

  filteredTrades.forEach((trade) => {
    const d = new Date(trade.created_at)
    if (d.getMonth() === month && d.getFullYear() === year) {
      const day = d.getDate()
      if (!dailyData[day]) dailyData[day] = { pnl: 0, trades: [] }
      dailyData[day].pnl += trade.pnl || 0
      dailyData[day].trades.push(trade)
    }
  })

  const monthTrades = Object.values(dailyData).flatMap((d: any) => d.trades)

  const totalTrades = monthTrades.length
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
    setSelectedDate(key)
    const list = filteredTrades.filter((trade) => {
      const d = new Date(trade.created_at)
      return (
        d.getFullYear() === year &&
        d.getMonth() === month &&
        d.getDate() === dayNum
      )
    })
    setSelectedTrades(list)
  }

  function renderCalendarDay(
    day: number | null,
    weekIndex: number,
    keySuffix: string
  ) {
    if (!day) {
      return (
        <div
          key={`empty-${weekIndex}-${keySuffix}`}
          className="aspect-square w-full min-h-0 flex flex-col items-center justify-center text-xs md:text-sm p-1 md:p-2 relative rounded-xl border border-white/10 bg-white/5"
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
          aspect-square w-full min-h-0 flex flex-col items-center justify-center text-xs md:text-sm p-1 md:p-2 relative z-10 cursor-pointer
          rounded-xl border border-white/10
          transition hover:scale-[1.03]
          ${selectedDate === dayKey ? "ring-2 ring-blue-400 ring-inset" : ""}
          ${data?.pnl > 0 ? "bg-emerald-500/25 border-emerald-400/40" : ""}
          ${data?.pnl < 0 ? "bg-red-500/25 border-red-400/40" : ""}
          ${!data ? "bg-white/5" : ""}
        `}
      >
        <div className="flex flex-col items-center justify-center overflow-hidden w-full max-w-full leading-tight">
          <div className="truncate text-center text-[10px] md:text-xs text-gray-300 w-full leading-tight">
            {day}
          </div>

          {data ? (
            <div className="w-full truncate text-center text-[10px] md:text-xs leading-tight">
              <div
                className={`truncate text-center font-semibold leading-tight ${
                  data.pnl > 0
                    ? "text-emerald-400"
                    : data.pnl < 0
                      ? "text-red-400"
                      : ""
                }`}
              >
                {formatPNL(data.pnl)}
              </div>
              <div className="truncate text-center text-gray-400 text-[10px] md:text-xs leading-tight">
                {data.trades.length} trades
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

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-7xl mx-auto flex flex-col gap-4 md:flex-row md:gap-8 items-start">

          {/* LEFT SIDE (CALENDAR) */}
          <div className="w-full min-w-0 overflow-x-hidden md:w-[65%]">

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

            <div className="w-full max-w-xs mx-auto mb-3 md:mb-4">
              <select
                value={accountFilter}
                onChange={(e) => {
                  setAccountFilter(e.target.value)
                  setSelectedDate(null)
                  setSelectedTrades([])
                }}
                className="w-full bg-[#0f172a] border border-white/10 px-3 py-2 rounded text-white"
              >
                <option value="all">All Accounts</option>
                {accounts.map((acc) => (
                  <option key={acc}>{acc}</option>
                ))}
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
                const weekTotal = getWeekTotal(week)
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
          <div className="w-full md:w-[35%] md:max-w-[300px] space-y-4 mt-4 md:mt-[52px]">

            {/* STATS */}
            <div className="bg-white/5 p-5 rounded-xl border border-white/10">
              <h3 className="text-blue-400 font-semibold mb-3">Monthly Stats</h3>

              <div className="space-y-2 text-sm">
                <p>Total Trades: {totalTrades}</p>
                <p>Win Rate: {winRate.toFixed(1)}%</p>
                <p className={totalPnL > 0 ? "text-emerald-400" : totalPnL < 0 ? "text-red-400" : ""}>
                  Total P&L: {formatPNL(totalPnL)}
                </p>
              </div>
            </div>

            {selectedDate ? (
              <div className="mt-4">
                <h3 className="text-sm md:text-lg font-semibold mb-2 text-center">
                  Trades on {new Date(selectedDate + "T12:00:00").toLocaleDateString()}
                </h3>

                {selectedTrades.length === 0 ? (
                  <p className="text-center text-gray-400 text-sm">No trades this day</p>
                ) : (
                  <div className="flex flex-col gap-3">
                    {selectedTrades.map((trade) => (
                      <TradeCard key={trade.id} trade={trade} />
                    ))}
                  </div>
                )}
              </div>
            ) : null}

          </div>

        </div>

      </div>
    </>
  )
}