"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "@/lib/dailyCheckIn/dateKey"
import { fetchPsychologyDashboardCheckIns } from "@/lib/dailyCheckIn/repository"
import { waitForDailyCheckInAuthSession } from "@/lib/dailyCheckIn/authSession"
import {
  readRecentCheckInsCache,
  subscribeCheckInCaches,
  writeRecentCheckInsCache,
} from "@/lib/dailyCheckIn/sessionCache"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import { ensurePsychologyJournalTrades } from "@/lib/psychology/reports/journalTrades"
import type { PsychologyReportTrade } from "@/lib/psychology/reports/types"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

/** Stable empty dashboard trade list — do not pass inline `[]` (breaks hook deps). */
export const PSYCHOLOGY_JOURNAL_EMPTY_DASHBOARD_TRADES: ReadonlyArray<
  Record<string, unknown>
> = []

export function usePsychologyJournalInputs(
  userId: string | null | undefined,
  dashboardTrades: ReadonlyArray<Record<string, unknown>>
) {
  const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
  const end = todayCheckInDateKey()
  const [checkIns, setCheckIns] = useState<TraderDailyCheckIn[]>(() => {
    if (!userId || isDemoUserId(userId)) return []
    return readRecentCheckInsCache(userId, start, end) ?? []
  })
  const [trades, setTrades] = useState<PsychologyReportTrade[]>([])
  const [ready, setReady] = useState(() => {
    if (!userId || isDemoUserId(userId)) return true
    return readRecentCheckInsCache(userId, start, end) !== undefined
  })
  const [loadError, setLoadError] = useState<string | null>(null)
  const dashboardTradesRef = useRef(dashboardTrades)
  dashboardTradesRef.current = dashboardTrades

  const load = useCallback(async (_options?: { force?: boolean }) => {
    if (!userId) {
      setReady(true)
      return
    }
    if (isDemoUserId(userId)) {
      setCheckIns([])
      setTrades([])
      setReady(true)
      return
    }
    try {
      const authReady = await waitForDailyCheckInAuthSession(supabase)
      if (!authReady) {
        setLoadError("Sign in to load daily check-ins.")
        setReady(true)
        return
      }
      const windowStart = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const windowEnd = todayCheckInDateKey()
      const cached = readRecentCheckInsCache(userId, windowStart, windowEnd)
      if (cached !== undefined) {
        setCheckIns(cached)
        setReady(true)
      }
      const [journalTrades, loadedCheckIns] = await Promise.all([
        ensurePsychologyJournalTrades(userId, dashboardTradesRef.current),
        fetchPsychologyDashboardCheckIns(supabase, userId),
      ])
      writeRecentCheckInsCache(userId, windowStart, windowEnd, loadedCheckIns, {
        authVerified: true,
      })
      setTrades(journalTrades)
      setCheckIns(loadedCheckIns)
      setLoadError(null)
    } catch (error) {
      setLoadError(toUserFacingErrorMessage(error))
    } finally {
      setReady(true)
    }
  }, [userId])

  useEffect(() => {
    if (!userId) {
      setReady(true)
      return
    }
    if (isDemoUserId(userId)) {
      setReady(true)
      return
    }
    const cached = readRecentCheckInsCache(userId, start, end)
    if (cached === undefined) {
      setReady(false)
    }
    void load()
  }, [end, load, start, userId])

  useEffect(() => {
    return subscribeCheckInCaches(() => {
      if (!userId) return
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cached = readRecentCheckInsCache(userId, start, end)
      if (cached !== undefined) {
        setCheckIns(cached)
        setLoadError(null)
        setReady(true)
      }
    })
  }, [userId])

  useEffect(() => {
    if (!userId || isDemoUserId(userId)) return

    function onResume() {
      void load({ force: true })
    }

    function onVisibility() {
      if (document.visibilityState !== "visible") return
      onResume()
    }

    window.addEventListener("focus", onResume)
    window.addEventListener("pageshow", onResume)
    document.addEventListener("visibilitychange", onVisibility)
    return () => {
      window.removeEventListener("focus", onResume)
      window.removeEventListener("pageshow", onResume)
      document.removeEventListener("visibilitychange", onVisibility)
    }
  }, [load, userId])

  return {
    checkIns,
    trades,
    ready,
    loadError,
    refresh: () => load({ force: true }),
    setCheckIns,
  }
}
