"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import { supabase } from "@/lib/supabaseClient"
import { waitForDailyCheckInAuthSession } from "@/lib/dailyCheckIn/authSession"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "./dateKey.ts"
import { fetchPsychologyDashboardCheckIns } from "./repository.ts"
import {
  invalidateDailyCheckInSessionCache,
  isRecentCheckInsCacheAuthVerified,
  mergeCheckInsByDatePreferNewer,
  readRecentCheckInsCache,
  subscribeCheckInCaches,
  subscribeDailyCheckInNetworkRefresh,
  writeRecentCheckInsCache,
} from "./sessionCache.ts"
import type { TraderDailyCheckIn } from "./types.ts"

const rangeInFlight = new Map<string, Promise<TraderDailyCheckIn[]>>()

function rangeKey(
  userId: string,
  startDate: string,
  endDate: string,
  accountFilter: string | null
): string {
  return `${userId}:${accountFilter ?? "all"}:${startDate}:${endDate}`
}

export function useRecentDailyCheckIns(
  userId: string | null | undefined,
  options?: { accountFilter?: string | null }
) {
  const accountFilter = options?.accountFilter ?? null
  const endDate = todayCheckInDateKey()
  const startDate = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
  const [checkIns, setCheckIns] = useState<TraderDailyCheckIn[]>(() => {
    if (!userId) return []
    return readRecentCheckInsCache(userId, startDate, endDate) ?? []
  })
  const [isReady, setIsReady] = useState(() => {
    if (!userId || isDemoUserId(userId)) return true
    return readRecentCheckInsCache(userId, startDate, endDate) !== undefined
  })
  const [loadError, setLoadError] = useState<string | null>(null)
  const [checkInsAuthVerified, setCheckInsAuthVerified] = useState(() => {
    if (!userId || isDemoUserId(userId)) return true
    return isRecentCheckInsCacheAuthVerified(
      userId,
      checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW),
      todayCheckInDateKey()
    )
  })
  const generationRef = useRef(0)
  const boundUserIdRef = useRef<string | null>(null)

  const load = useCallback(
    async (options?: { force?: boolean }) => {
      if (!userId) {
        setCheckIns([])
        setIsReady(true)
        return
      }
      if (isDemoUserId(userId)) {
        setCheckIns([])
        setIsReady(true)
        return
      }

      const authReady = await waitForDailyCheckInAuthSession(supabase)
      if (!authReady) {
        setLoadError("Sign in to load daily check-ins.")
        setCheckIns([])
        setIsReady(true)
        return
      }

      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (user?.id !== userId) {
        setIsReady(false)
        return
      }

      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cachedBeforeFetch = readRecentCheckInsCache(userId, start, end)
      if (cachedBeforeFetch !== undefined) {
        setCheckIns(cachedBeforeFetch)
        setCheckInsAuthVerified(
          isRecentCheckInsCacheAuthVerified(userId, start, end)
        )
        setIsReady(true)
      }

      generationRef.current += 1
      const generation = generationRef.current
      const key = rangeKey(userId, start, end, accountFilter)
      const existing = rangeInFlight.get(key)
      const task =
        existing ??
        fetchPsychologyDashboardCheckIns(supabase, userId, {
          accountFilter,
        }).finally(() => {
          if (rangeInFlight.get(key) === task) {
            rangeInFlight.delete(key)
          }
        })
      if (!existing) rangeInFlight.set(key, task)

      try {
        const rows = await task
        if (generation !== generationRef.current) return
        const merged = mergeCheckInsByDatePreferNewer(
          rows,
          cachedBeforeFetch ?? []
        )
        writeRecentCheckInsCache(userId, start, end, merged, {
          authVerified: true,
        })
        setCheckIns(merged)
        setCheckInsAuthVerified(true)
        setLoadError(null)
        setIsReady(true)
      } catch (error) {
        if (generation !== generationRef.current) return
        setLoadError(toUserFacingErrorMessage(error))
        if (readRecentCheckInsCache(userId, start, end) === undefined) {
          setCheckIns([])
          setIsReady(true)
        }
      }
    },
    [accountFilter, userId]
  )

  const accountFilterRef = useRef(accountFilter)
  useEffect(() => {
    if (!userId) {
      boundUserIdRef.current = null
      setCheckIns([])
      setIsReady(true)
      return
    }
    const userChanged = boundUserIdRef.current !== userId
    const accountFilterChanged = accountFilterRef.current !== accountFilter
    accountFilterRef.current = accountFilter
    if (userChanged) {
      boundUserIdRef.current = userId
      invalidateDailyCheckInSessionCache()
      setIsReady(false)
      void load({ force: true })
      return
    }
    if (accountFilterChanged) {
      void load({ force: true })
      return
    }
    void load()
  }, [accountFilter, load, startDate, endDate, userId])

  useEffect(() => {
    return subscribeCheckInCaches(() => {
      if (!userId) return
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cached = readRecentCheckInsCache(userId, start, end)
      if (cached !== undefined) {
        setCheckIns(cached)
        setCheckInsAuthVerified(
          isRecentCheckInsCacheAuthVerified(userId, start, end)
        )
        setIsReady(true)
      }
    })
  }, [userId])

  useEffect(() => {
    if (!userId || isDemoUserId(userId)) return
    return subscribeDailyCheckInNetworkRefresh(() => {
      void load({ force: true })
    })
  }, [load, userId])

  useEffect(() => {
    if (!userId || isDemoUserId(userId)) return

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session?.user?.id !== userId) return
      void load({ force: true })
    })

    return () => subscription.unsubscribe()
  }, [load, userId])

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
    startDate,
    endDate,
    isReady,
    checkInsAuthVerified,
    loadError,
    refresh: () => load({ force: true }),
  }
}
