"use client"

import { useMemo, useState } from "react"
import Link from "next/link"
import {
  buildCheckInHistorySummaries,
  checkInHistoryDayMatchesFilter,
  formatCheckInHistoryDateLabel,
  formatCheckInHistoryTradeLine,
  psychologyPreviewParts,
  type CheckInHistoryContentFilter,
} from "@/lib/psychology/checkInHistory"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import type { PsychologyReportTrade } from "@/lib/psychology/reports/types"
import { formatHours } from "@/lib/psychology/display"
import { stressLabel } from "@/lib/dailyCheckIn/types"

const FILTERS: CheckInHistoryContentFilter[] = ["all", "trades", "psychology"]

type CheckInHistoryHomeProps = {
  checkIns: TraderDailyCheckIn[]
  trades: PsychologyReportTrade[]
  loadError?: string | null
  onRetry?: () => void
}

export default function CheckInHistoryHome({
  checkIns,
  trades,
  loadError,
  onRetry,
}: CheckInHistoryHomeProps) {
  const [filter, setFilter] = useState<CheckInHistoryContentFilter>("all")
  const summaries = useMemo(
    () => buildCheckInHistorySummaries(checkIns, trades),
    [checkIns, trades]
  )
  const filtered = summaries.filter((row) =>
    checkInHistoryDayMatchesFilter(row, filter)
  )

  if (loadError) {
    return (
      <p className="text-sm text-red-400">
        {loadError}{" "}
        {onRetry ? (
          <button type="button" className="underline" onClick={() => onRetry()}>
            Retry
          </button>
        ) : null}
      </p>
    )
  }

  if (summaries.length === 0) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center">
        <p className="font-medium text-white">No history yet</p>
        <p className="mt-1 text-sm text-gray-500">
          Log daily check-ins and trades to build your history.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-4" data-testid="checkInHistory.list">
      <div className="flex rounded-lg border border-white/10 bg-white/5 p-0.5">
        {FILTERS.map((value) => (
          <button
            key={value}
            type="button"
            onClick={() => setFilter(value)}
            className={`flex-1 rounded-md px-2 py-1.5 text-xs font-semibold capitalize ${
              filter === value ? "bg-blue-500/25 text-white" : "text-gray-400"
            }`}
          >
            {value === "psychology" ? "Psychology" : value === "trades" ? "Trades" : "All"}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
          No days match this filter.
        </div>
      ) : (
        <ul className="space-y-2">
          {filtered.map((day) => (
            <li key={day.dateKey}>
              <Link
                href={`/check-in-history/${day.dateKey}`}
                className="block rounded-xl border border-white/10 bg-white/5 p-4 hover:border-white/20 hover:bg-white/[0.07]"
              >
                <p className="font-semibold text-white">
                  {formatCheckInHistoryDateLabel(day.dateKey)}
                </p>
                <DayPreview summary={day} filter={filter} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function DayPreview({
  summary,
  filter,
}: {
  summary: ReturnType<typeof buildCheckInHistorySummaries>[number]
  filter: CheckInHistoryContentFilter
}) {
  if (filter === "trades") {
    return (
      <p className="mt-1 text-xs text-gray-400">
        {formatCheckInHistoryTradeLine(summary)}
      </p>
    )
  }
  if (filter === "psychology") {
    const line = summary.checkIn
      ? psychologyPreviewParts(summary.checkIn).join(" · ")
      : ""
    return line ? (
      <p className="mt-1 text-xs text-gray-400">{line}</p>
    ) : null
  }

  const lines: string[] = []
  if (summary.checkIn) {
    const c = summary.checkIn
    const legacy: string[] = []
    if (c.sleepHours != null) legacy.push(`${formatHours(c.sleepHours)} Sleep`)
    if (c.focusLevel != null) legacy.push(`Focus ${c.focusLevel}/5`)
    if (c.stressLevel != null) {
      legacy.push(`Stress ${stressLabel(c.stressLevel)}`)
    }
    if (legacy.length) lines.push(legacy.join(" · "))
  }
  if (summary.tradeCount > 0) {
    lines.push(formatCheckInHistoryTradeLine(summary))
  } else if (!summary.checkIn) {
    lines.push("No check-in or trades")
  }
  return lines.length ? (
    <p className="mt-1 text-xs text-gray-400">{lines.join(" · ")}</p>
  ) : null
}
