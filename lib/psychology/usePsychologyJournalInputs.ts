"use client"

import { useCallback, useEffect, useState } from "react"
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

export function usePsychologyJournalInputs(
  userId: string | null | undefined,
  dashboardTrades: ReadonlyArray<Record<string, unknown>>
) {
  const [checkIns, setCheckIns] = useState<TraderDailyCheckIn[]>([])
  const [trades, setTrades] = useState<PsychologyReportTrade[]>([])
  const [ready, setReady] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)

  const load = useCallback(async (options?: { force?: boolean }) => {
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
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cached = !options?.force
        ? readRecentCheckInsCache(userId, start, end)
        : undefined
      const [journalTrades, loadedCheckIns] = await Promise.all([
        ensurePsychologyJournalTrades(userId, dashboardTrades),
        cached !== undefined
          ? Promise.resolve(cached)
          : fetchPsychologyDashboardCheckIns(supabase, userId),
      ])
      if (cached === undefined) {
        writeRecentCheckInsCache(userId, start, end, loadedCheckIns, {
          authVerified: true,
        })
      }
      setTrades(journalTrades)
      setCheckIns(loadedCheckIns)
      setLoadError(null)
    } catch (error) {
      setLoadError(toUserFacingErrorMessage(error))
    } finally {
      setReady(true)
    }
  }, [dashboardTrades, userId])

  useEffect(() => {
    setReady(false)
    void load()
  }, [load])

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
