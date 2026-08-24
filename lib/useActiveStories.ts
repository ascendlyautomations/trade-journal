"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  getSoonestStoryExpiryMs,
  pruneExpiredStories,
  fetchActiveStoriesForUserIds,
  type StoriesByUserMap,
} from "@/lib/activeStories"
import {
  readStoriesSession,
  writeStoriesSession,
} from "@/lib/storiesSessionCache"
import { isDemoModeActive } from "@/lib/demo/demoMode"

function normalizeUserIds(userIds: string[]): string[] {
  return [...new Set(userIds.map((id) => String(id).trim()).filter(Boolean))]
}

/**
 * Shared active-story state: fetch, realtime refresh, and client-side expiry pruning.
 */
export function useActiveStories(
  userIds: string[],
  enabled = true,
  autoLoad = true
) {
  const userIdsKey = useMemo(
    () => normalizeUserIds(userIds).sort().join(","),
    [userIds]
  )

  const [storiesByUser, setStoriesByUser] = useState<StoriesByUserMap>(() => {
    if (!enabled) return {}
    return readStoriesSession(userIdsKey) ?? {}
  })

  const loadStories = useCallback(async () => {
    const ids = normalizeUserIds(userIdsRef.current)
    if (ids.length === 0) {
      setStoriesByUser({})
      return
    }

    const { storiesByUser: next, error } = await fetchActiveStoriesForUserIds(
      supabase,
      ids
    )

    if (error) {
      console.error("[useActiveStories] fetch failed:", error)
      return
    }

    setStoriesByUser(next)
    writeStoriesSession(userIdsKey, next)
  }, [userIdsKey])

  const userIdsRef = useRef(userIds)
  userIdsRef.current = userIds

  useEffect(() => {
    if (!enabled) {
      setStoriesByUser({})
      return
    }
    const warm = readStoriesSession(userIdsKey)
    if (warm) {
      setStoriesByUser(warm)
      return
    }
    if (!autoLoad) return
    void loadStories()
  }, [autoLoad, enabled, loadStories, userIdsKey])

  useEffect(() => {
    if (!enabled || isDemoModeActive()) return

    const ids = normalizeUserIds(userIdsRef.current)
    if (ids.length === 0) return
    if (!autoLoad && Object.keys(storiesByUser).length === 0) return

    const channel = supabase.channel(`active-stories:${userIdsKey}`)

    for (const userId of ids) {
      channel.on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "stories",
          filter: `user_id=eq.${userId}`,
        },
        () => {
          void loadStories()
        }
      )
    }

    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [autoLoad, enabled, loadStories, storiesByUser, userIdsKey])

  useEffect(() => {
    if (!enabled) return

    let timeoutId: number | undefined

    const scheduleExpiry = (map: StoriesByUserMap) => {
      if (timeoutId != null) {
        window.clearTimeout(timeoutId)
      }

      const expiresAt = getSoonestStoryExpiryMs(map)
      if (expiresAt == null) return

      const delay = Math.max(0, expiresAt - Date.now()) + 100
      timeoutId = window.setTimeout(() => {
        setStoriesByUser((current) => {
          const pruned = pruneExpiredStories(current)
          scheduleExpiry(pruned)
          return pruned
        })
      }, delay)
    }

    scheduleExpiry(storiesByUser)

    return () => {
      if (timeoutId != null) {
        window.clearTimeout(timeoutId)
      }
    }
  }, [enabled, storiesByUser])

  return { storiesByUser, loadStories, setStoriesByUser }
}
