"use client"

import { useMemo, useState } from "react"
import { toDateKey } from "@/lib/formatDate"
import { formatCurrency } from "@/lib/formatCurrency"
import type { WithdrawalsByDateEntry } from "@/lib/withdrawalsPresentation"

type WithdrawalsCalendarProps = {
  byDate: Map<string, WithdrawalsByDateEntry>
  selectedDateKey: string | null
  onSelectDateKey: (dateKey: string | null) => void
}

export default function WithdrawalsCalendar({
  byDate,
  selectedDateKey,
  onSelectDateKey,
}: WithdrawalsCalendarProps) {
  const now = new Date()
  const [monthDate, setMonthDate] = useState(
    () => new Date(now.getFullYear(), now.getMonth(), 1)
  )

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
    cells.push({
      date: new Date(monthDate.getFullYear(), monthDate.getMonth(), d),
    })
  }
  while (cells.length % 7 !== 0) cells.push({ date: null })

  const weeks: Array<Array<{ date: Date | null }>> = []
  for (let i = 0; i < cells.length; i += 7) {
    weeks.push(cells.slice(i, i + 7))
  }

  const monthTotal = useMemo(() => {
    let total = 0
    for (let d = 1; d <= totalDays; d++) {
      const key = toDateKey(monthDate.getFullYear(), monthDate.getMonth(), d)
      total += byDate.get(key)?.total ?? 0
    }
    return total
  }, [byDate, monthDate, totalDays])

  return (
    <section className="tt-web-calendar space-y-4 rounded-xl border border-white/10 bg-white/[0.03] p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
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
        <p className="text-xs text-gray-400">
          Month total{" "}
          <span className="font-semibold tabular-nums text-white">
            {formatCurrency(monthTotal)}
          </span>
        </p>
      </div>

      {selectedDateKey ? (
        <div className="flex items-center justify-between rounded-lg border border-blue-400/30 bg-blue-500/10 px-3 py-2 text-xs text-blue-100">
          <span>
            Showing {selectedDateKey}
            {byDate.get(selectedDateKey)
              ? ` · ${formatCurrency(byDate.get(selectedDateKey)!.total)}`
              : ""}
          </span>
          <button
            type="button"
            className="underline"
            onClick={() => onSelectDateKey(null)}
          >
            Clear
          </button>
        </div>
      ) : null}

      <div className="grid grid-cols-7 gap-2 text-center text-xs text-gray-400">
        {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((d) => (
          <p key={d}>{d}</p>
        ))}
      </div>

      <div className="space-y-2">
        {weeks.map((week, weekIndex) => (
          <div key={`week-${weekIndex}`} className="grid grid-cols-7 gap-2">
            {week.map((cell, idx) => {
              if (!cell.date) {
                return (
                  <div
                    key={`empty-${weekIndex}-${idx}`}
                    className="h-14 rounded-lg border border-transparent bg-transparent"
                  />
                )
              }
              const key = toDateKey(
                cell.date.getFullYear(),
                cell.date.getMonth(),
                cell.date.getDate()
              )
              const entry = byDate.get(key)
              const active = selectedDateKey === key
              const hasWithdrawals = entry != null && entry.count > 0
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() =>
                    onSelectDateKey(active ? null : hasWithdrawals ? key : null)
                  }
                  disabled={!hasWithdrawals}
                  className={`flex h-14 flex-col items-center justify-center rounded-lg border px-1 py-1 text-center text-xs transition ${
                    hasWithdrawals
                      ? "cursor-pointer border-green-400/40 bg-green-500/20 text-white hover:border-green-300/50"
                      : "cursor-default border-white/10 bg-[#0b1220] text-gray-300"
                  } ${active ? "ring-2 ring-blue-400" : ""}`}
                >
                  <span className="text-sm font-semibold leading-tight">
                    {cell.date.getDate()}
                  </span>
                  {hasWithdrawals ? (
                    <span className="mt-0.5 w-full truncate text-[10px] font-medium text-white/90">
                      {formatCurrency(entry.total)}
                    </span>
                  ) : null}
                </button>
              )
            })}
          </div>
        ))}
      </div>
    </section>
  )
}
