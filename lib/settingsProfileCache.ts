/** Extended settings profile row — memory + sessionStorage for the session (event invalidation). */

const STORAGE_KEY = "tj_settings_profile_v1"

type SettingsProfileEntry = {
  userId: string
  profile: Record<string, unknown>
  fetchedAt: number
}

const memory = new Map<string, SettingsProfileEntry>()

function readStorage(): Record<string, SettingsProfileEntry> {
  if (typeof window === "undefined") return {}
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, SettingsProfileEntry>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

function writeStorage(entries: Record<string, SettingsProfileEntry>) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
  } catch {
    // quota / private mode — memory cache still works
  }
}

function hasEntry(entry: SettingsProfileEntry | undefined): entry is SettingsProfileEntry {
  return entry != null
}

export function readSettingsProfileCache(
  userId: string
): Record<string, unknown> | null {
  const key = userId.trim()
  if (!key) return null

  const mem = memory.get(key)
  if (hasEntry(mem)) return mem.profile

  const stored = readStorage()[key]
  if (hasEntry(stored)) {
    memory.set(key, stored)
    return stored.profile
  }

  return null
}

export function writeSettingsProfileCache(
  userId: string,
  profile: Record<string, unknown> | null
) {
  const key = userId.trim()
  if (!key || profile == null) return

  const entry: SettingsProfileEntry = {
    userId: key,
    profile,
    fetchedAt: Date.now(),
  }
  memory.set(key, entry)

  const stored = readStorage()
  stored[key] = entry
  writeStorage(stored)
}

export function clearSettingsProfileCache(userId: string) {
  const key = userId.trim()
  if (!key) return
  memory.delete(key)
  const stored = readStorage()
  delete stored[key]
  writeStorage(stored)
}

export function clearAllSettingsProfileCaches() {
  memory.clear()
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
}
