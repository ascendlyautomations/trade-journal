"use client"

import { useCallback, useEffect, useSyncExternalStore } from "react"
import { supabase } from "@/lib/supabaseClient"
import type { Achievement } from "@/lib/achievementTypes"
import {
  ensureOwnAchievementsLoaded,
  getOwnAchievementsError,
  getOwnAchievementsSnapshot,
  isOwnAchievementsLoading,
  subscribeUserAchievementsCache,
} from "@/lib/userAchievementsCache"

const EMPTY: Achievement[] = []

function getServerSnapshot(): Achievement[] {
  return EMPTY
}

export function useUserAchievements(userId: string | null | undefined) {
  const subscribe = useCallback(
    (listener: () => void) => subscribeUserAchievementsCache(listener),
    []
  )

  const achievements = useSyncExternalStore(
    subscribe,
    () => getOwnAchievementsSnapshot(userId) ?? EMPTY,
    getServerSnapshot
  )

  const loading = useSyncExternalStore(
    subscribe,
    () => isOwnAchievementsLoading(userId),
    () => false
  )

  const error = useSyncExternalStore(
    subscribe,
    () => getOwnAchievementsError(userId),
    () => null
  )

  useEffect(() => {
    if (!userId) return
    void ensureOwnAchievementsLoaded(supabase, userId)
  }, [userId, achievements])

  const refresh = useCallback(async () => {
    if (!userId) return EMPTY
    return ensureOwnAchievementsLoaded(supabase, userId, { force: true })
  }, [userId])

  return { achievements, loading, error, refresh }
}
