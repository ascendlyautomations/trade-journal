"use client"

import { useMemo, useState } from "react"

type TradeLike = {
  id: string | number
  created_at: string
  pnl: number | null
  ticker?: string | null
  direction?: string | null
  image_url?: string | null
  rr?: number | string | null
  points?: number | string | null
  session?: string | null
  mode?: string | null
  account_type?: string | null
  account_size?: string | null
  account_id?: string | number | null
  strategy?: string | null
}

type CalendarProps = {
  trades: TradeLike[]
  showAccountFilter?: boolean
  showControls?: boolean
}

function dayKey(date: Date) {
  return date.toISOString().slice(0, 10)
}

const formatMoney = (num: number | null | undefined) => {
  if (num == null) return "$0.00"
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(num)
}

function tradeImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export default function Calendar({
  trades,
  showAccountFilter = false,
  showControls = false,
}: CalendarProps) {
  void showAccountFilter
  void showControls

  const now = new Date()
  const [monthDate, setMonthDate] = useState(
    new Date(now.getFullYear(), now.getMonth(), 1)
  )
  const [selectedDay, setSelectedDay] = useState<string | null>(null)
  const [selectedTrade, setSelectedTrade] = useState<TradeLike | null>(null)

  const byDay = useMemo(() => {
    const map: Record<string, TradeLike[]> = {}
    for (const t of trades || []) {
      const d = new Date(t.created_at)
      if (Number.isNaN(d.getTime())) continue
      const key = dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate()))
      if (!map[key]) map[key] = []
      map[key].push(t)
    }
    return map
  }, [trades])

  const monthLabel = monthDate.toLocaleString(undefined, {
    month: "long",
    year: "numeric",
  })

  const monthStart = new Date(monthDate.getFullYear(), monthDate.getMonth(), 1)
  const monthEnd = new Date(monthDate.getFullYear(), monthDate.getMonth() + 1, 0)
  const startWeekday = monthStart.getDay()
  const totalDays = monthEnd.getDate()

  const cells: Array<{ date: Date | null }> = []
  for (let i = 0; i < startWeekday; i++) cells.push({ date: null })
  for (let d = 1; d <= totalDays; d++) {
    cells.push({ date: new Date(monthDate.getFullYear(), monthDate.getMonth(), d) })
  }

  const selectedTrades = selectedDay ? byDay[selectedDay] || [] : []
  const dayTrades = selectedTrades
  const sortedDayTrades = useMemo(() => {
    return [...dayTrades].sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
  }, [dayTrades])
  const totalPnl = dayTrades.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)

  return (
    <div className="space-y-4 rounded-xl border border-white/10 bg-white/[0.03] p-4">
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={() =>
            setMonthDate(
              new Date(monthDate.getFullYear(), monthDate.getMonth() - 1, 1)
            )
          }
          className="rounded bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
        >
          Prev
        </button>
        <p className="text-sm font-medium text-white">{monthLabel}</p>
        <button
          type="button"
          onClick={() =>
            setMonthDate(
              new Date(monthDate.getFullYear(), monthDate.getMonth() + 1, 1)
            )
          }
          className="rounded bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
        >
          Next
        </button>
      </div>

      <div className="grid grid-cols-7 gap-2 text-center text-xs text-gray-400">
        {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((d) => (
          <p key={d}>{d}</p>
        ))}
      </div>

      <div className="grid grid-cols-7 gap-2">
        {cells.map((cell, idx) => {
          if (!cell.date) {
            return <div key={`empty-${idx}`} className="h-14 rounded bg-transparent" />
          }
          const key = dayKey(cell.date)
          const dayTrades = byDay[key] || []
          const totalPnl = dayTrades.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)
          const active = selectedDay === key
          return (
            <button
              key={key}
              type="button"
              onClick={() => setSelectedDay(key)}
              className={`h-14 rounded p-1 text-left text-xs transition ${
                dayTrades.length === 0
                  ? "bg-white/5 text-gray-400"
                  : totalPnl >= 0
                  ? "bg-green-500/20 text-green-200"
                  : "bg-red-500/20 text-red-200"
              } ${active ? "ring-1 ring-blue-400" : ""}`}
            >
              <p>{cell.date.getDate()}</p>
              {dayTrades.length ? (
                <p className="mt-1 text-[10px] font-medium">
                  {totalPnl >= 0 ? "+" : ""}
                  {totalPnl.toFixed(0)}
                </p>
              ) : null}
            </button>
          )
        })}
      </div>

      <div className="mx-auto mt-6 w-full max-w-2xl rounded-xl border border-white/10 bg-[#020617]/80 p-5 backdrop-blur-md">
        {!selectedDay ? (
          <p className="text-sm text-gray-400">Select a day to view trades.</p>
        ) : dayTrades.length === 0 ? (
          <p className="text-sm text-gray-400">No trades on this day.</p>
        ) : (
          <div>
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-lg font-semibold text-white">
                Trades on {selectedDay}
              </h2>
              <span className="text-sm text-gray-400">
                {sortedDayTrades.length} trades
              </span>
            </div>

            <div className="mb-4 text-xl font-semibold">
              <span className={totalPnl >= 0 ? "text-green-400" : "text-red-400"}>
                {formatMoney(totalPnl)}
              </span>
            </div>

            <div className="mt-3 space-y-3">
              {sortedDayTrades.map((trade) => {
                const img = tradeImageSrc(trade.image_url)
                const pnl = Number(trade.pnl) || 0
                const modeLower = String(trade.mode ?? "").toLowerCase().trim()
                const acctId =
                  trade.account_id != null && String(trade.account_id).trim() !== ""
                    ? `#${String(trade.account_id).trim()}`
                    : null
                const accountLine = [trade.account_type, trade.account_size, acctId]
                  .filter((x) => x != null && String(x).trim() !== "")
                  .join(" ")

                return (
                  <div
                    key={String(trade.id)}
                    role="button"
                    tabIndex={0}
                    onClick={() => setSelectedTrade(trade)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault()
                        setSelectedTrade(trade)
                      }
                    }}
                    className="flex cursor-pointer items-start gap-3 rounded-xl border border-white/10 bg-black/40 p-3 transition hover:bg-black/60 sm:gap-4 sm:p-4"
                  >
                    {img ? (
                      <img
                        src={img}
                        alt=""
                        className="h-16 w-16 shrink-0 rounded-lg border border-white/10 object-cover sm:h-20 sm:w-20"
                      />
                    ) : null}

                    <div className="min-w-0 flex-1">
                      <p className="font-semibold text-white">
                        {trade.ticker || "—"} • {trade.direction || "—"}
                      </p>
                      <p className="text-sm text-gray-400">
                        {new Date(trade.created_at).toLocaleTimeString()}
                      </p>
                      <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-gray-400">
                        {trade.rr != null && trade.rr !== "" ? (
                          <span>RR: {trade.rr}</span>
                        ) : null}
                        {trade.points != null && trade.points !== "" ? (
                          <span>Pts: {trade.points}</span>
                        ) : null}
                        {trade.session ? <span>{trade.session}</span> : null}
                        {modeLower === "backtest" ? (
                          <span className="text-blue-300/90">Backtest</span>
                        ) : null}
                      </div>
                      {modeLower !== "backtest" && accountLine ? (
                        <p className="mt-1 text-xs text-gray-500">{accountLine}</p>
                      ) : null}
                      {trade.strategy ? (
                        <p className="mt-1 text-xs text-blue-400">
                          {trade.strategy}
                        </p>
                      ) : null}
                    </div>

                    <div className="shrink-0 text-right">
                      <p
                        className={`text-sm font-bold tabular-nums sm:text-base ${
                          pnl >= 0 ? "text-green-400" : "text-red-400"
                        }`}
                      >
                        {formatMoney(pnl)}
                      </p>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )}
      </div>

      {selectedTrade ? (
        <div
          className="fixed inset-0 z-[200] flex items-center justify-center bg-black/70 p-4"
          onClick={() => setSelectedTrade(null)}
        >
          <div
            className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between">
              <p className="text-sm font-semibold text-white">Trade</p>
              <button
                type="button"
                onClick={() => setSelectedTrade(null)}
                className="text-gray-400 hover:text-white"
              >
                ✕
              </button>
            </div>
            {(() => {
              const img = tradeImageSrc(selectedTrade.image_url)
              const pnl = Number(selectedTrade.pnl) || 0
              const modeLower = String(selectedTrade.mode ?? "")
                .toLowerCase()
                .trim()
              const acctId =
                selectedTrade.account_id != null &&
                String(selectedTrade.account_id).trim() !== ""
                  ? `#${String(selectedTrade.account_id).trim()}`
                  : null
              const accountLine = [
                selectedTrade.account_type,
                selectedTrade.account_size,
                acctId,
              ]
                .filter((x) => x != null && String(x).trim() !== "")
                .join(" ")
              return (
                <>
                  {img ? (
                    <img
                      src={img}
                      alt=""
                      className="mb-3 max-h-48 w-full rounded-lg border border-white/10 object-contain"
                    />
                  ) : null}
                  <p className="text-sm text-gray-300">
                    {selectedTrade.ticker || "—"} •{" "}
                    {selectedTrade.direction || "—"}
                  </p>
                  <p className="mt-1 text-sm text-gray-400">
                    {new Date(selectedTrade.created_at).toLocaleString()}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-gray-400">
                    {selectedTrade.rr != null && selectedTrade.rr !== "" ? (
                      <span>RR: {selectedTrade.rr}</span>
                    ) : null}
                    {selectedTrade.points != null &&
                    selectedTrade.points !== "" ? (
                      <span>Pts: {selectedTrade.points}</span>
                    ) : null}
                    {selectedTrade.session ? (
                      <span>{selectedTrade.session}</span>
                    ) : null}
                    {modeLower === "backtest" ? (
                      <span className="text-blue-300/90">Backtest</span>
                    ) : null}
                  </div>
                  {modeLower !== "backtest" && accountLine ? (
                    <p className="mt-2 text-xs text-gray-500">{accountLine}</p>
                  ) : null}
                  {selectedTrade.strategy ? (
                    <p className="mt-1 text-xs text-blue-400">
                      {selectedTrade.strategy}
                    </p>
                  ) : null}
                  <p
                    className={`mt-3 text-lg font-bold tabular-nums ${
                      pnl >= 0 ? "text-green-400" : "text-red-400"
                    }`}
                  >
                    {formatMoney(pnl)}
                  </p>
                </>
              )
            })()}
          </div>
        </div>
      ) : null}
    </div>
  )
}
