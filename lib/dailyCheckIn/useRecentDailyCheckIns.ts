"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "./dateKey.ts"
import { fetchCheckInsInRange } from "./repository.ts"
import {
  readRecentCheckInsCache,
  subscribeCheckInCaches,
  writeRecentCheckInsCache,
} from "./sessionCache.ts"
import type { TraderDailyCheckIn } from "./types.ts"

const rangeInFlight = new Map<string, Promise<TraderDailyCheckIn[]>>()

function rangeKey(userId: string, startDate: string, endDate: string): string {
  return `${userId}:${startDate}:${endDate}`
}

export function useRecentDailyCheckIns(userId: string | null | undefined) {
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
  const generationRef = useRef(0)

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

      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      if (!options?.force) {
        const cached = readRecentCheckInsCache(userId, start, end)
        if (cached !== undefined) {
          setCheckIns(cached)
          setIsReady(true)
          return
        }
      }

      generationRef.current += 1
      const generation = generationRef.current
      const key = rangeKey(userId, start, end)
      const existing = rangeInFlight.get(key)
      const task =
        existing ??
        fetchCheckInsInRange(supabase, userId, start, end).finally(() => {
          if (rangeInFlight.get(key) === task) {
            rangeInFlight.delete(key)
          }
        })
      if (!existing) rangeInFlight.set(key, task)

      try {
        const rows = await task
        if (generation !== generationRef.current) return
        writeRecentCheckInsCache(userId, start, end, rows)
        setCheckIns(rows)
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
    [userId]
  )

  useEffect(() => {
    void load()
  }, [load, startDate, endDate])

  useEffect(() => {
    return subscribeCheckInCaches(() => {
      if (!userId) return
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cached = readRecentCheckInsCache(userId, start, end)
      if (cached !== undefined) {
        setCheckIns(cached)
        setIsReady(true)
      }
    })
  }, [userId])

  return {
    checkIns,
    startDate,
    endDate,
    isReady,
    loadError,
    refresh: () => load({ force: true }),
  }
}
