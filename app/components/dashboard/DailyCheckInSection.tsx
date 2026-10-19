"use client"

import { Suspense, useCallback, useEffect, useState } from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
import Button from "@/app/components/ui/Button"
import { DAILY_CHECK_IN_QUERY_PARAM } from "@/lib/dailyCheckIn/constants"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isDemoUserId } from "@/lib/demo/constants"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { upsertDailyCheckIn } from "@/lib/dailyCheckIn/repository"
import {
  draftFromCheckIn,
  emptyCheckInDraft,
  stressLabel,
  type TraderDailyCheckInDraft,
} from "@/lib/dailyCheckIn/types"
import { formatSleepHoursInput, validateCheckInDraft } from "@/lib/dailyCheckIn/validation"
import { useTodayDailyCheckIn } from "@/lib/dailyCheckIn/useTodayDailyCheckIn"
import DailyCheckInModal from "./DailyCheckInModal"

type DailyCheckInSectionProps = {
  userId: string
}

function MetricChip({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <span className="tt-dash-checkin-chip inline-flex items-center gap-1 rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[11px] font-medium text-gray-200">
      <span className="text-gray-400">{label}</span>
      <span className="tabular-nums text-white">{value}</span>
    </span>
  )
}

export function DailyCheckInSectionSkeleton() {
  return (
    <div
      className="tt-dash-checkin h-[4.5rem] animate-pulse rounded-xl border border-white/10 bg-white/5"
      aria-hidden
    />
  )
}

export default function DailyCheckInSection({
  userId,
}: DailyCheckInSectionProps) {
  const {
    dateKey,
    checkIn,
    isReady,
    loadError,
    isCompletedToday,
    applySaved,
    refresh,
  } = useTodayDailyCheckIn(userId)

  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<TraderDailyCheckInDraft>(() =>
    emptyCheckInDraft(dateKey)
  )
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [formEpoch, setFormEpoch] = useState(0)

  const searchParams = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()

  const seedAndOpen = useCallback(() => {
    setDraft(
      checkIn && checkIn.checkInDate === dateKey
        ? draftFromCheckIn(checkIn)
        : emptyCheckInDraft(dateKey)
    )
    setSaveError(null)
    setFormEpoch((value) => value + 1)
    setOpen(true)
  }, [checkIn, dateKey])

  useEffect(() => {
    if (!isReady) return
    if (searchParams.get(DAILY_CHECK_IN_QUERY_PARAM) !== "1") return
    seedAndOpen()
    const next = new URLSearchParams(searchParams.toString())
    next.delete(DAILY_CHECK_IN_QUERY_PARAM)
    const qs = next.toString()
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false })
  }, [isReady, pathname, router, searchParams, seedAndOpen])

  async function handleSave() {
    if (isDemoModeActive() || isDemoUserId(userId)) {
      requestDemoSignup("save")
      return
    }

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
      applySaved(saved)
      setOpen(false)
      notifyGettingStartedChecklistMaybeCompleted()
    } catch (error) {
      setSaveError(toUserFacingErrorMessage(error))
    } finally {
      setSaving(false)
    }
  }

  if (!isReady && !checkIn) {
    return <DailyCheckInSectionSkeleton />
  }

  return (
    <>
      <section
        className="tt-dash-checkin rounded-xl border border-white/10 bg-white/5 px-3.5 py-3 backdrop-blur-md md:px-4"
        data-testid="dailyCheckIn.card"
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span
                className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm ${
                  isCompletedToday
                    ? "bg-emerald-500/15 text-emerald-400"
                    : "bg-blue-500/15 text-blue-300"
                }`}
                aria-hidden
              >
                {isCompletedToday ? "✓" : "☀"}
              </span>
              <div className="min-w-0">
                <h2 className="text-sm font-semibold text-white">
                  Daily Check-In
                </h2>
                <p className="text-xs text-gray-400">
                  {isCompletedToday
                    ? "Completed today"
                    : "Log how you're feeling today"}
                </p>
              </div>
            </div>
            {isCompletedToday && checkIn ? (
              <div className="mt-2 flex flex-wrap gap-1.5 pl-10">
                <MetricChip
                  label="Sleep"
                  value={`${formatSleepHoursInput(checkIn.sleepHours)}h`}
                />
                <MetricChip
                  label="Stress"
                  value={
                    checkIn.stressLevel != null
                      ? stressLabel(checkIn.stressLevel)
                      : "—"
                  }
                />
                <MetricChip
                  label="Energy"
                  value={
                    checkIn.energyLevel != null
                      ? `${checkIn.energyLevel}/5`
                      : "—"
                  }
                />
                <MetricChip
                  label="Focus"
                  value={
                    checkIn.focusLevel != null ? `${checkIn.focusLevel}/5` : "—"
                  }
                />
              </div>
            ) : null}
            {loadError && !checkIn ? (
              <p className="mt-2 pl-10 text-xs text-red-400">
                {loadError}{" "}
                <button
                  type="button"
                  className="underline"
                  onClick={() => void refresh()}
                >
                  Retry
                </button>
              </p>
            ) : null}
          </div>
          <Button
            type="button"
            variant={isCompletedToday ? "secondary" : "primary"}
            size="sm"
            onClick={seedAndOpen}
            className="min-h-11 shrink-0"
          >
            {isCompletedToday ? "Edit" : "Check In"}
          </Button>
        </div>
      </section>

      {open ? (
        <DailyCheckInModal
          key={`${dateKey}:${formEpoch}`}
          open={open}
          dateKey={dateKey}
          draft={draft}
          onDraftChange={setDraft}
          saving={saving}
          errorMessage={saveError}
          historyHref="/check-in-history"
          onClose={() => {
            if (saving) return
            setOpen(false)
          }}
          onSave={() => void handleSave()}
        />
      ) : null}
    </>
  )
}

export function DailyCheckInDashboardSlot({ userId }: { userId: string }) {
  return (
    <Suspense fallback={<DailyCheckInSectionSkeleton />}>
      <DailyCheckInSection userId={userId} />
    </Suspense>
  )
}
