"use client"

import { useMemo, useState } from "react"
import Link from "next/link"
import DailyCheckInModal from "@/app/components/dashboard/DailyCheckInModal"
import {
  buildCheckInDayDetail,
  formatCheckInDayProfitFactor,
  formatCheckInHistoryDayTitle,
} from "@/lib/psychology/checkInHistory"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import type { PsychologyReportTrade } from "@/lib/psychology/reports/types"
import {
  formatPsychologyMoney,
  formatPsychologyWinRate,
} from "@/lib/psychology/reports/format"
import { stressLabel } from "@/lib/dailyCheckIn/types"
import { formatSleepHoursInput } from "@/lib/dailyCheckIn/validation"
import { upsertDailyCheckIn } from "@/lib/dailyCheckIn/repository"
import type { TraderDailyCheckInDraft } from "@/lib/dailyCheckIn/types"
import { draftFromCheckIn, emptyCheckInDraft } from "@/lib/dailyCheckIn/types"
import { validateCheckInDraft } from "@/lib/dailyCheckIn/validation"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

type CheckInDayDetailProps = {
  userId: string
  dateKey: string
  checkIns: TraderDailyCheckIn[]
  trades: PsychologyReportTrade[]
  onCheckInSaved: (saved: TraderDailyCheckIn) => void
}

export default function CheckInDayDetail({
  userId,
  dateKey,
  checkIns,
  trades,
  onCheckInSaved,
}: CheckInDayDetailProps) {
  const detail = useMemo(
    () => buildCheckInDayDetail(dateKey, checkIns, trades),
    [checkIns, dateKey, trades]
  )
  const [editOpen, setEditOpen] = useState(false)
  const [draft, setDraft] = useState<TraderDailyCheckInDraft>(() =>
    detail.checkIn
      ? draftFromCheckIn(detail.checkIn)
      : emptyCheckInDraft(dateKey)
  )
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  function openEdit() {
    setDraft(
      detail.checkIn
        ? draftFromCheckIn(detail.checkIn)
        : emptyCheckInDraft(dateKey)
    )
    setSaveError(null)
    setEditOpen(true)
  }

  async function handleSave() {
    const nextDraft = { ...draft, checkInDate: dateKey }
    const message = validateCheckInDraft(nextDraft)
    if (message) {
      setSaveError(message)
      return
    }
    setSaving(true)
    setSaveError(null)
    try {
      const saved = await upsertDailyCheckIn(supabase, userId, nextDraft)
      onCheckInSaved(saved)
      setEditOpen(false)
    } catch (error) {
      setSaveError(toUserFacingErrorMessage(error))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-4" data-testid="checkInDay.detail">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-blue-200">
          {formatCheckInHistoryDayTitle(dateKey)}
        </h1>
        <button
          type="button"
          onClick={openEdit}
          className="rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-sm font-medium text-white hover:bg-white/10"
        >
          Edit Check-In
        </button>
      </div>

      <section className="rounded-xl border border-white/10 bg-white/5 p-4">
        <h2 className="text-sm font-semibold text-white">Daily Check-In</h2>
        {detail.checkIn ? (
          <>
            <MetricGrid
              rows={[
                ["Sleep", sleepText(detail.checkIn.sleepHours)],
                ["Sleep Quality", ratingText(detail.checkIn.sleepQuality)],
                ["Morning", ratingText(detail.checkIn.morningRating)],
                [
                  "Stress",
                  detail.checkIn.stressLevel != null
                    ? stressLabel(detail.checkIn.stressLevel)
                    : "—",
                ],
                ["Energy", ratingText(detail.checkIn.energyLevel)],
                ["Focus", ratingText(detail.checkIn.focusLevel)],
              ]}
            />
            {detail.checkIn.notes?.trim() ? (
              <p className="mt-3 text-sm text-gray-400">{detail.checkIn.notes}</p>
            ) : null}
          </>
        ) : (
          <p className="mt-2 text-sm text-gray-400">No check-in logged for this day.</p>
        )}
      </section>

      <section className="rounded-xl border border-white/10 bg-white/5 p-4">
        <h2 className="text-sm font-semibold text-white">Trading Performance</h2>
        {detail.trades.length === 0 ? (
          <p className="mt-2 text-sm text-gray-400">No trades on this day.</p>
        ) : (
          <MetricGrid
            rows={[
              ["P&L", formatPsychologyMoney(detail.metrics.totalPnL)],
              ["Trades", String(detail.metrics.tradeCount)],
              ["Win Rate", formatPsychologyWinRate(detail.metrics.winRate)],
              ["Avg Trade", formatPsychologyMoney(detail.metrics.averagePnL ?? 0)],
              ["Profit Factor", formatCheckInDayProfitFactor(detail.metrics)],
            ]}
          />
        )}
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-semibold text-white">Trades</h2>
        {detail.trades.length === 0 ? (
          <p className="text-sm text-gray-500">No trades to show.</p>
        ) : (
          detail.trades.map((trade) => (
            <Link
              key={trade.id}
              href={`/trade/${trade.id}`}
              className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-4 py-3 hover:bg-white/[0.07]"
            >
              <div>
                <p className="text-sm font-semibold text-white">
                  {trade.mode ?? "Trade"}
                </p>
                <p className="text-xs text-gray-500">{trade.account_type ?? "—"}</p>
              </div>
              <p
                className={`text-sm font-semibold tabular-nums ${
                  trade.pnl >= 0 ? "text-emerald-400" : "text-red-400"
                }`}
              >
                {formatPsychologyMoney(trade.pnl)}
              </p>
            </Link>
          ))
        )}
      </section>

      {editOpen ? (
        <DailyCheckInModal
          open={editOpen}
          dateKey={dateKey}
          draft={draft}
          onDraftChange={setDraft}
          saving={saving}
          errorMessage={saveError}
          onClose={() => {
            if (!saving) setEditOpen(false)
          }}
          onSave={() => void handleSave()}
        />
      ) : null}
    </div>
  )
}

function MetricGrid({ rows }: { rows: [string, string][] }) {
  return (
    <div className="mt-3 grid grid-cols-2 gap-3">
      {rows.map(([label, value]) => (
        <div key={label}>
          <p className="text-[10px] uppercase text-gray-500">{label}</p>
          <p className="text-sm font-semibold text-white">{value}</p>
        </div>
      ))}
    </div>
  )
}

function ratingText(value: number | null | undefined): string {
  return value != null ? `${value}/5` : "—"
}

function sleepText(hours: number | null | undefined): string {
  return hours != null ? `${formatSleepHoursInput(hours)}h` : "—"
}
