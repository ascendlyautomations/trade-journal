"use client"

import { useCallback, useEffect, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "@/lib/dailyCheckIn/dateKey"
import { fetchCheckInsInRange } from "@/lib/dailyCheckIn/repository"
import { readRecentCheckInsCache, writeRecentCheckInsCache } from "@/lib/dailyCheckIn/sessionCache"
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

  const load = useCallback(async () => {
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
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cached = readRecentCheckInsCache(userId, start, end)
      const [journalTrades, loadedCheckIns] = await Promise.all([
        ensurePsychologyJournalTrades(userId, dashboardTrades),
        cached
          ? Promise.resolve(cached)
          : fetchCheckInsInRange(supabase, userId, start, end),
      ])
      if (!cached) {
        writeRecentCheckInsCache(userId, start, end, loadedCheckIns)
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

  return { checkIns, trades, ready, loadError, refresh: load, setCheckIns }
}
