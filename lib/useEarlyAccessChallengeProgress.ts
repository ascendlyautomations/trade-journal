"use client"

import { useCallback, useEffect, useSyncExternalStore } from "react"
import type { EarlyAccessProgress } from "@/lib/earlyAccess"
import { fetchCurrentEarlyAccessProgress } from "@/lib/earlyAccessClient"

/**
 * Shared Founding Challenge progress store so the dashboard card and the
 * navbar Getting Started entry read one consistent snapshot without
 * duplicating fetch or task logic.
 */
let cachedProgress: EarlyAccessProgress | null = null
let loaded = false
let inFlight: Promise<void> | null = null
const listeners = new Set<() => void>()

function notify() {
  for (const listener of listeners) listener()
}

function loadProgress(force = false): Promise<void> {
  if (loaded && !force && !inFlight) return Promise.resolve()
  if (!inFlight) {
    inFlight = fetchCurrentEarlyAccessProgress()
      .then((next) => {
        cachedProgress = next
      })
      .catch((error) => {
        console.error("[earlyAccessChallengeProgress]", error)
      })
      .then(() => {
        loaded = true
        inFlight = null
        notify()
      })
  }
  return inFlight
}

export function refreshEarlyAccessChallengeProgress(): Promise<void> {
  return loadProgress(true)
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function useEarlyAccessChallengeProgress(enabled: boolean): {
  progress: EarlyAccessProgress | null
  loaded: boolean
  refresh: () => Promise<void>
} {
  const progress = useSyncExternalStore(
    subscribe,
    () => cachedProgress,
    () => null
  )
  const isLoaded = useSyncExternalStore(
    subscribe,
    () => loaded,
    () => false
  )

  useEffect(() => {
    if (enabled) void loadProgress()
  }, [enabled])

  const refresh = useCallback(() => loadProgress(true), [])

  return { progress, loaded: isLoaded, refresh }
}
