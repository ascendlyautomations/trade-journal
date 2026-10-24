"use client"

import { Suspense, useCallback, useEffect, useState } from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
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
  type TraderDailyCheckInDraft,
} from "@/lib/dailyCheckIn/types"
import { validateCheckInDraft } from "@/lib/dailyCheckIn/validation"
import { requestDailyCheckInNetworkRefresh } from "@/lib/dailyCheckIn/sessionCache"
import { useTodayDailyCheckIn } from "@/lib/dailyCheckIn/useTodayDailyCheckIn"
import DailyCheckInModal from "./DailyCheckInModal"

type DailyCheckInSectionProps = {
  userId: string
}

const quickActionCardClass =
  "tt-dash-checkin flex h-full min-h-[3.75rem] w-full min-w-0 items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-left backdrop-blur-md transition hover:bg-white/[0.07]"

export function DailyCheckInSectionSkeleton() {
  return (
    <div
      className="tt-dash-checkin h-full min-h-[3.75rem] animate-pulse rounded-xl border border-white/10 bg-white/5"
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
      requestDailyCheckInNetworkRefresh()
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

  const subtitle = loadError && !checkIn
    ? "Couldn't load today's check-in"
    : isCompletedToday
      ? "Completed today"
      : "Log how you're feeling today"

  return (
    <div className="min-w-0">
      <button
        type="button"
        className={quickActionCardClass}
        data-testid="dailyCheckIn.card"
        onClick={() => {
          if (loadError && !checkIn) {
            void refresh()
            return
          }
          seedAndOpen()
        }}
      >
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
        <span className="min-w-0 flex-1">
          <h2 className="truncate text-sm font-semibold text-white">
            Daily Check-In
          </h2>
          <p className="line-clamp-2 text-xs text-gray-400">{subtitle}</p>
        </span>
        <QuickActionChevron />
      </button>

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
    </div>
  )
}

function QuickActionChevron() {
  return (
    <svg
      viewBox="0 0 20 20"
      aria-hidden
      className="h-3.5 w-3.5 shrink-0 text-gray-500"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
    >
      <path d="M7 5l5 5-5 5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function DailyCheckInDashboardSlot({ userId }: { userId: string }) {
  return (
    <Suspense fallback={<DailyCheckInSectionSkeleton />}>
      <DailyCheckInSection userId={userId} />
    </Suspense>
  )
}
