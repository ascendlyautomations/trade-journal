"use client"

import { useCallback, useEffect, useSyncExternalStore } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureUserStreaksLoaded,
  getUserStreaksSnapshot,
  isUserStreaksLoading,
  subscribeUserStreaksCache,
  type UserStreaksSnapshot,
} from "@/lib/userStreaksCache"
import { subscribeAppDataCache } from "@/lib/appDataCache"

const EMPTY_SNAPSHOT: UserStreaksSnapshot | null = null

function getServerSnapshot(): UserStreaksSnapshot | null {
  return EMPTY_SNAPSHOT
}

export function useUserStreaks(userId: string | null | undefined) {
  const subscribe = useCallback(
    (listener: () => void) => {
      const unsubStreaks = subscribeUserStreaksCache(listener)
      const unsubTrades = subscribeAppDataCache(listener)
      return () => {
        unsubStreaks()
        unsubTrades()
      }
    },
    []
  )

  const snapshot = useSyncExternalStore(
    subscribe,
    () => getUserStreaksSnapshot(userId),
    getServerSnapshot
  )

  const loading = useSyncExternalStore(
    subscribe,
    () => isUserStreaksLoading(userId),
    () => false
  )

  useEffect(() => {
    if (!userId) return
    void ensureUserStreaksLoaded(supabase, userId)
  }, [userId, snapshot])

  const refresh = useCallback(async () => {
    if (!userId) return null
    return ensureUserStreaksLoaded(supabase, userId, { force: true })
  }, [userId])

  return { snapshot, loading, refresh }
}
