import type { SupabaseClient } from "@supabase/supabase-js"
import type { Achievement } from "./achievementTypes"
import { fetchOwnAchievements } from "./achievements"
import { isDemoUserId } from "./demo/constants"
import { getDemoAchievementsForUser } from "./demo/demoAchievements"

type CacheEntry = {
  userId: string
  data: Achievement[]
  invalidated: boolean
  loading: boolean
  error: string | null
}

const achievementsByUser = new Map<string, CacheEntry>()
const inFlight = new Map<string, Promise<Achievement[]>>()
const listeners = new Set<() => void>()

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

export function subscribeUserAchievementsCache(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getOwnAchievementsSnapshot(
  userId: string | null | undefined
): Achievement[] | null {
  if (!userId) return null
  const entry = achievementsByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  return entry.data
}

export function getOwnAchievementsError(
  userId: string | null | undefined
): string | null {
  if (!userId) return null
  const entry = achievementsByUser.get(userId)
  if (!entry || entry.invalidated) return null
  return entry.error
}

export function isOwnAchievementsLoading(
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  if (getOwnAchievementsSnapshot(userId)) return false
  return achievementsByUser.get(userId)?.loading === true
}

export function invalidateUserAchievementsCache(userId: string) {
  const key = userId.trim()
  if (!key) return
  const entry = achievementsByUser.get(key)
  if (!entry || entry.invalidated) return
  achievementsByUser.set(key, { ...entry, invalidated: true })
  notify()
}

export function clearAllUserAchievementsCaches() {
  achievementsByUser.clear()
  inFlight.clear()
  notify()
}

export function patchUserAchievementsCache(
  userId: string,
  updater: (current: Achievement[]) => Achievement[]
) {
  const key = userId.trim()
  if (!key) return
  const entry = achievementsByUser.get(key)
  if (!entry || entry.invalidated) return
  const next = updater(entry.data)
  achievementsByUser.set(key, { ...entry, data: next, invalidated: false })
  notify()
}

export async function ensureOwnAchievementsLoaded(
  _client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<Achievement[]> {
  const key = userId.trim()
  if (!key) return []

  if (!options?.force) {
    const cached = getOwnAchievementsSnapshot(key)
    if (cached) return cached
  }

  const existingFlight = inFlight.get(key)
  if (existingFlight && !options?.force) {
    return existingFlight
  }

  const existing = achievementsByUser.get(key)
  if (!options?.force && existing?.loading) {
    return existing.data
  }

  achievementsByUser.set(key, {
    userId: key,
    data: existing?.data ?? [],
    invalidated: false,
    loading: true,
    error: null,
  })
  notify()

  const promise = (async () => {
    if (isDemoUserId(key)) {
      return getDemoAchievementsForUser(key) as Achievement[]
    }

    const { data, error } = await fetchOwnAchievements(key)
    if (error) {
      throw new Error(error.message || "Could not load achievements.")
    }
    return (data || []) as Achievement[]
  })()

  inFlight.set(key, promise)

  try {
    const data = await promise
    achievementsByUser.set(key, {
      userId: key,
      data,
      invalidated: false,
      loading: false,
      error: null,
    })
    notify()
    return data
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not load achievements."
    achievementsByUser.set(key, {
      userId: key,
      data: existing?.data ?? [],
      invalidated: false,
      loading: false,
      error: message,
    })
    notify()
    return existing?.data ?? []
  } finally {
    inFlight.delete(key)
  }
}
