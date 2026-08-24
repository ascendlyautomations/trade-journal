import type { SupabaseClient } from "@supabase/supabase-js"
import {
  DEFAULT_NOTIFICATION_PREFERENCES,
  mapNotificationPreferencesRow,
  NOTIFICATION_PREFERENCES_SELECT,
  type NotificationPreferenceKey,
  type NotificationPreferences,
} from "./notificationPreferences.ts"

const STORAGE_KEY = "tj_notification_preferences_v1"
const SOFT_STALE_MS = 5 * 60_000

type PreferencesEntry = {
  userId: string
  preferences: NotificationPreferences
  fetchedAt: number
}

const memory = new Map<string, PreferencesEntry>()
const listeners = new Set<() => void>()
const inflightByViewer = new Map<string, Promise<NotificationPreferences>>()

/** @internal */
export function resetNotificationPreferencesCacheForTests() {
  memory.clear()
  inflightByViewer.clear()
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
}

function readStorage(): Record<string, PreferencesEntry> {
  if (typeof window === "undefined") return {}
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, PreferencesEntry>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

function writeStorage(entries: Record<string, PreferencesEntry>) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
  } catch {
    // ignore
  }
}

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

export function subscribeNotificationPreferencesCache(listener: () => void) {
  listeners.add(listener)
  return () => {
    void listeners.delete(listener)
  }
}

export function getCachedNotificationPreferences(
  userId: string | null | undefined
): NotificationPreferences | null {
  if (!userId) return null
  const key = userId.trim()

  const mem = memory.get(key)
  if (mem) {
    return mem.preferences
  }

  const stored = readStorage()[key]
  if (stored) {
    memory.set(key, stored)
    return stored.preferences
  }

  return null
}

export function writeNotificationPreferencesCache(
  userId: string,
  preferences: NotificationPreferences
) {
  const key = userId.trim()
  if (!key) return

  const entry: PreferencesEntry = {
    userId: key,
    preferences,
    fetchedAt: Date.now(),
  }
  memory.set(key, entry)

  const stored = readStorage()
  stored[key] = entry
  writeStorage(stored)
  notify()
}

export function clearNotificationPreferencesCache(userId: string) {
  const key = userId.trim()
  if (!key) return
  memory.delete(key)
  const stored = readStorage()
  delete stored[key]
  writeStorage(stored)
  notify()
}

export function clearAllNotificationPreferencesCaches() {
  memory.clear()
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
  notify()
}

async function fetchNotificationPreferencesFromDb(
  client: SupabaseClient,
  key: string
): Promise<NotificationPreferences> {
  const cached = getCachedNotificationPreferences(key)

  const { data, error } = await client
    .from("notification_preferences")
    .select(NOTIFICATION_PREFERENCES_SELECT)
    .eq("user_id", key)
    .maybeSingle()

  if (error) {
    console.error("ensureNotificationPreferencesLoaded:", error)
    if (cached) return cached
    return mapNotificationPreferencesRow(
      { user_id: key, ...DEFAULT_NOTIFICATION_PREFERENCES },
      key
    )
  }

  const preferences = mapNotificationPreferencesRow(data, key)
  writeNotificationPreferencesCache(key, preferences)
  return preferences
}

export async function ensureNotificationPreferencesLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<NotificationPreferences> {
  const key = userId.trim()
  if (!key) {
    return mapNotificationPreferencesRow(null, "")
  }

  const cached = getCachedNotificationPreferences(key)
  if (cached && !options?.force) {
    const entry = memory.get(key)
    const age = entry ? Date.now() - entry.fetchedAt : SOFT_STALE_MS + 1
    if (age <= SOFT_STALE_MS) return cached
    if (!inflightByViewer.has(key)) {
      void fetchNotificationPreferencesFromDb(client, key).catch(() => cached)
    }
    return cached
  }

  const existing = inflightByViewer.get(key)
  if (existing && !options?.force) return existing

  const inflight = fetchNotificationPreferencesFromDb(client, key).finally(() => {
    if (inflightByViewer.get(key) === inflight) {
      inflightByViewer.delete(key)
    }
  })
  inflightByViewer.set(key, inflight)
  return inflight
}

export async function updateNotificationPreference(
  client: SupabaseClient,
  userId: string,
  patch: Partial<Record<NotificationPreferenceKey, boolean>>
): Promise<NotificationPreferences | null> {
  const key = userId.trim()
  if (!key || Object.keys(patch).length === 0) return null

  const current =
    getCachedNotificationPreferences(key) ??
    (await ensureNotificationPreferencesLoaded(client, key))

  const next = {
    ...current,
    ...patch,
    updated_at: new Date().toISOString(),
  }

  const { data, error } = await client
    .from("notification_preferences")
    .upsert(
      {
        user_id: key,
        ...patch,
        updated_at: next.updated_at,
      },
      { onConflict: "user_id" }
    )
    .select(NOTIFICATION_PREFERENCES_SELECT)
    .single()

  if (error) {
    console.error("updateNotificationPreference:", error)
    return null
  }

  const saved = mapNotificationPreferencesRow(data, key)
  writeNotificationPreferencesCache(key, saved)
  return saved
}
