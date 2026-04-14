"use client"
import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function CalendarPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedDay, setSelectedDay] = useState<number | null>(null)

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
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-7xl mx-auto flex gap-8 items-start">

          {/* LEFT SIDE (CALENDAR) */}
          <div className="flex-1">

            {/* HEADER — NOW CENTERED OVER CALENDAR ONLY */}
            <div className="flex justify-center items-center gap-6 mb-6">
              <button onClick={() => changeMonth(-1)} className="text-xl hover:text-blue-400">&lt;</button>

              <h2 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
                {currentDate.toLocaleString("default", { month: "long" })} {year}
              </h2>

              <button onClick={() => changeMonth(1)} className="text-xl hover:text-blue-400">&gt;</button>
            </div>

            {/* DAYS HEADER */}
            <div className="grid grid-cols-7 gap-3 mb-2 text-center text-gray-400 text-sm">
              {["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].map(d => (
                <div key={d}>{d}</div>
              ))}
            </div>

            {/* CALENDAR GRID */}
            <div className="space-y-2">
              {weeks.map((week, weekIndex) => {
                const weekTotal = getWeekTotal(week)
                return (
                  <div key={weekIndex} className="mb-2">
                    <div className="grid grid-cols-7 gap-3">
                      {week.map((day, dayIndex) => {
                        if (!day) {
                          return (
                            <div
                              key={`empty-${weekIndex}-${dayIndex}`}
                              className="aspect-square rounded-xl border border-white/10 bg-white/5"
                            />
                          )
                        }

                        const data = dailyData[day]

                        return (
                          <div
                            key={`day-${weekIndex}-${dayIndex}`}
                            className={`
                              aspect-square rounded-xl border border-white/10 p-2
                              flex flex-col justify-between cursor-pointer
                              transition hover:scale-[1.03]

                              ${data?.pnl > 0 ? "bg-emerald-500/25 border-emerald-400/40" : ""}
                              ${data?.pnl < 0 ? "bg-red-500/25 border-red-400/40" : ""}
                              ${!data ? "bg-white/5" : ""}
                            `}
                          >
                            <div className="text-xs text-gray-300">{day}</div>

                            {data && (
                              <div className="text-center text-xs">
                                <div className={`font-semibold ${
                                  data.pnl > 0 ? "text-emerald-400" :
                                  data.pnl < 0 ? "text-red-400" : ""
                                }`}>
                                  {formatPNL(data.pnl)}
                                </div>
                                <div className="text-gray-400 text-[10px]">
                                  {data.trades.length} trades
                                </div>
                              </div>
                            )}
                          </div>
                        )
                      })}
                    </div>

                    <div className="mt-1 flex justify-end pr-2">
                      <span
                        className={`rounded-full px-3 py-1 text-xs font-semibold ${
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
          <div className="w-[300px] space-y-4 mt-[52px]">

            {/* FILTER */}
            <select
              value={accountFilter}
              onChange={(e) => setAccountFilter(e.target.value)}
              className="w-full bg-[#0f172a] border border-white/10 px-3 py-2 rounded text-white"
            >
              <option value="all">All Accounts</option>
              {accounts.map((acc) => (
                <option key={acc}>{acc}</option>
              ))}
            </select>

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

          </div>

        </div>

      </div>
    </>
  )
}