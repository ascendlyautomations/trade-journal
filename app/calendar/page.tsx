"use client"
import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function CalendarPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedDay, setSelectedDay] = useState<number | null>(null)
  const [selectedImage, setSelectedImage] = useState<string | null>(null)

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setTrades([])
      return
    }

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

      if (!dailyData[day]) {
        dailyData[day] = { pnl: 0, trades: [] }
      }

      dailyData[day].pnl += trade.pnl || 0
      dailyData[day].trades.push(trade)
    }
  })

  const monthTrades = Object.values(dailyData).flatMap((d: any) => d.trades)

  const totalTrades = monthTrades.length
  const wins = monthTrades.filter((t: any) => t.pnl > 0)
  const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
  const totalPnL = monthTrades.reduce((sum: number, t: any) => sum + (t.pnl || 0), 0)

  const totalCells = 42
  const calendarDays = []

  for (let i = 0; i < totalCells; i++) {
    const dayNumber = i - firstDayOfMonth + 1
    calendarDays.push(dayNumber > 0 && dayNumber <= daysInMonth ? dayNumber : null)
  }

  function changeMonth(offset: number) {
    const newDate = new Date(currentDate)
    newDate.setMonth(newDate.getMonth() + offset)
    setCurrentDate(newDate)
    setSelectedDay(null)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e293b] to-[#312e81] text-white p-10">

        {/* HEADER */}
        <div className="grid grid-cols-3 mb-8 items-center">

          {/* LEFT = EMPTY */}
          <div></div>

          {/* CENTERED OVER CALENDAR */}
          <div className="flex justify-center items-center gap-4 text-xl font-semibold col-span-1">
            <button onClick={() => changeMonth(-1)}>&lt;</button>

            <span className="text-blue-300">
              {currentDate.toLocaleString("default", { month: "long" })} {year}
            </span>

            <button onClick={() => changeMonth(1)}>&gt;</button>
          </div>

          {/* RIGHT DROPDOWN */}
          <div className="flex justify-center">
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
          </div>

        </div>

        <div className="grid lg:grid-cols-3 gap-8">

          {/* CALENDAR */}
          <div className="lg:col-span-2">

            <div className="grid grid-cols-7 gap-4 mb-4 text-center text-blue-300">
              {["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].map(d => <div key={d}>{d}</div>)}
            </div>

            <div className="grid grid-cols-7 gap-4">
              {calendarDays.map((day, index) => {
                if (!day) {
                  return <div key={index} className="h-28 bg-white/5 rounded-xl" />
                }

                const data = dailyData[day]

                return (
                  <div
                    key={index}
                    onClick={() => setSelectedDay(day)}
                    className={`
                      h-28 rounded-xl border border-white/10 backdrop-blur-md 
                      cursor-pointer hover:scale-105 transition
                      flex flex-col justify-between p-3
                      ${data?.pnl > 0 ? "bg-green-300/15" : ""}
                      ${data?.pnl < 0 ? "bg-red-300/15" : ""}
                      ${!data ? "bg-white/5" : ""}
                    `}
                  >
                    {/* DATE TOP LEFT */}
                    <div className="text-sm text-blue-300">{day}</div>

                    {/* CENTERED PNL */}
                    {data && (
                      <div className="flex flex-col items-center justify-center text-xs">
                        <div>{formatPNL(data.pnl)}</div>
                        <div>{data.trades.length} trades</div>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>

          </div>

          {/* RIGHT PANEL */}
          <div className="space-y-6">

            {/* MONTH STATS (LEFT ALIGNED) */}
            <div className="bg-white/5 border border-white/10 p-5 rounded-xl">
              <h3 className="text-blue-300 font-semibold mb-3">Monthly Stats</h3>

              <div className="space-y-2 text-sm text-left">
                <p>Total Trades: {totalTrades}</p>
                <p>Win Rate: {winRate.toFixed(1)}%</p>
                <p>Total P&L: {formatPNL(totalPnL)}</p>
              </div>
            </div>

            {/* TRADES */}
            {selectedDay && dailyData[selectedDay] && (
              <div className="bg-white/5 border border-white/10 p-5 rounded-xl">

                <h3 className="text-blue-300 font-semibold mb-3">
                  Trades on {currentDate.toLocaleString("default", { month: "long" })} {selectedDay}, {year}
                </h3>

                {dailyData[selectedDay].trades.map((trade: any) => (
                  <div
                    key={trade.id}
                    onClick={() => {
                      if (trade.image_url) {
                        setSelectedImage(
                          `https://fobudrkniacatvilbofw.supabase.co/storage/v1/object/public/screenshots/${trade.image_url}`
                        )
                      }
                    }}
                    className="border border-white/10 p-3 rounded mb-3 cursor-pointer hover:bg-white/5"
                  >
                    <p className="text-sm">
                      <b>{trade.ticker}</b> | {trade.direction}
                    </p>

                    <p className={`text-sm ${
                      trade.pnl > 0 ? "text-green-300" :
                      trade.pnl < 0 ? "text-red-300" : ""
                    }`}>
                      P&L: {formatPNL(trade.pnl)} | RR: {trade.rr}
                      {trade.contracts != null
                        ? ` | Contracts: ${trade.contracts}`
                        : ""}
                    </p>

                    <p className="text-xs text-gray-400">
                      {trade.session}
                    </p>

                    <p className="text-xs mt-1">
                      {trade.notes}
                    </p>
                  </div>
                ))}

              </div>
            )}

          </div>

        </div>

        {/* IMAGE MODAL */}
        {selectedImage && (
          <div
            className="fixed inset-0 bg-black bg-opacity-80 flex items-center justify-center"
            onClick={() => setSelectedImage(null)}
          >
            <img src={selectedImage} className="max-w-[90%] max-h-[90%] rounded-lg" />
          </div>
        )}

      </div>
    </>
  )
}