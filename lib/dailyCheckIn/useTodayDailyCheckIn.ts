"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { todayCheckInDateKey } from "./dateKey.ts"
import { fetchTodayCheckIn } from "./repository.ts"
import {
  readTodayCheckInCache,
  resolveTodayCheckInFromCaches,
  subscribeCheckInCaches,
  writeTodayCheckInCache,
} from "./sessionCache.ts"
import type { TraderDailyCheckIn } from "./types.ts"
import { isCompleteCheckIn } from "./validation.ts"

const DATE_POLL_MS = 60_000

export function useTodayDailyCheckIn(userId: string | null | undefined) {
  const [dateKey, setDateKey] = useState(() => todayCheckInDateKey())
  const [checkIn, setCheckIn] = useState<TraderDailyCheckIn | null>(() => {
    if (!userId) return null
    const cached = resolveTodayCheckInFromCaches(userId, todayCheckInDateKey())
    return cached === undefined ? null : cached
  })
  const [isReady, setIsReady] = useState(() => {
    if (!userId || isDemoUserId(userId)) return true
    return (
      resolveTodayCheckInFromCaches(userId, todayCheckInDateKey()) !== undefined
    )
  })
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const generationRef = useRef(0)
  const inFlightRef = useRef<Promise<void> | null>(null)

  const syncDateKey = useCallback(() => {
    const next = todayCheckInDateKey()
    setDateKey((current) => (current === next ? current : next))
    return next
  }, [])

  const load = useCallback(
    async (options?: { force?: boolean }) => {
      const resolvedDate = syncDateKey()
      if (!userId) {
        setCheckIn(null)
        setIsReady(true)
        setIsRefreshing(false)
        return
      }
      if (isDemoUserId(userId)) {
        setCheckIn(null)
        setIsReady(true)
        setIsRefreshing(false)
        return
      }

      if (!options?.force) {
        const cached = resolveTodayCheckInFromCaches(userId, resolvedDate)
        if (cached !== undefined) {
          if (readTodayCheckInCache(userId, resolvedDate) === undefined) {
            writeTodayCheckInCache(userId, resolvedDate, cached)
          }
          setCheckIn(cached)
          setIsReady(true)
          return
        }
      }

      if (inFlightRef.current && !options?.force) {
        await inFlightRef.current
        return
      }

      generationRef.current += 1
      const generation = generationRef.current
      setIsRefreshing(true)

      const task = (async () => {
        try {
          const loaded = await fetchTodayCheckIn(supabase, userId, resolvedDate)
          if (generation !== generationRef.current) return
          writeTodayCheckInCache(userId, resolvedDate, loaded)
          setCheckIn(loaded)
          setLoadError(null)
          setIsReady(true)
        } catch (error) {
          if (generation !== generationRef.current) return
          setLoadError(toUserFacingErrorMessage(error))
          if (readTodayCheckInCache(userId, resolvedDate) === undefined) {
            setCheckIn(null)
            setIsReady(true)
          }
        } finally {
          if (generation === generationRef.current) {
            setIsRefreshing(false)
          }
        }
      })()

      inFlightRef.current = task
      try {
        await task
      } finally {
        if (inFlightRef.current === task) {
          inFlightRef.current = null
        }
      }
    },
    [syncDateKey, userId]
  )

  useEffect(() => {
    setCheckIn((current) => {
      if (current && current.checkInDate !== dateKey) return null
      return current
    })
    void load()
  }, [load, dateKey, userId])

  useEffect(() => {
    return subscribeCheckInCaches(() => {
      if (!userId) return
      const today = todayCheckInDateKey()
      const cached = resolveTodayCheckInFromCaches(userId, today)
      if (cached === undefined) return
      setDateKey(today)
      setCheckIn(cached)
      setIsReady(true)
    })
  }, [userId])

  useEffect(() => {
    function onResume() {
      const next = syncDateKey()
      if (next !== dateKey) return
      void load({ force: false })
    }

    function onVisibility() {
      if (document.visibilityState !== "visible") return
      onResume()
    }

    window.addEventListener("focus", onResume)
    window.addEventListener("pageshow", onResume)
    document.addEventListener("visibilitychange", onVisibility)
    const timer = window.setInterval(() => {
      syncDateKey()
    }, DATE_POLL_MS)

    return () => {
      window.removeEventListener("focus", onResume)
      window.removeEventListener("pageshow", onResume)
      document.removeEventListener("visibilitychange", onVisibility)
      window.clearInterval(timer)
    }
  }, [dateKey, load, syncDateKey])

  const applySaved = useCallback(
    (saved: TraderDailyCheckIn) => {
      const today = todayCheckInDateKey()
      if (!userId || saved.checkInDate !== today) return
      writeTodayCheckInCache(userId, today, saved)
      setDateKey(today)
      setCheckIn(saved)
      setLoadError(null)
      setIsReady(true)
    },
    [userId]
  )

  const isCompletedToday =
    checkIn != null &&
    checkIn.checkInDate === dateKey &&
    isCompleteCheckIn(checkIn)

  return {
    dateKey,
    checkIn,
    isReady,
    isRefreshing,
    loadError,
    isCompletedToday,
    refresh: () => load({ force: true }),
    applySaved,
  }
}
