/** Persist last-known profile slice for instant post-login bootstrap (session lifetime). */

const STORAGE_KEY = "tj_user_bootstrap_v1"

type BootstrapEntry = {
  userId: string
  profile: unknown
  fetchedAt: number
}

const memory = new Map<string, BootstrapEntry>()

function readStorage(): Record<string, BootstrapEntry> {
  if (typeof window === "undefined") return {}
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, BootstrapEntry>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

function writeStorage(entries: Record<string, BootstrapEntry>) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
  } catch {
    // quota / private mode — memory cache still works
  }
}

function hasEntry(entry: BootstrapEntry | undefined): entry is BootstrapEntry {
  return entry != null
}

export function readUserBootstrapProfile(userId: string): unknown | null {
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

export function writeUserBootstrapProfile(userId: string, profile: unknown) {
  const key = userId.trim()
  if (!key || profile == null) return

  const entry: BootstrapEntry = {
    userId: key,
    profile,
    fetchedAt: Date.now(),
  }
  memory.set(key, entry)

  const stored = readStorage()
  stored[key] = entry
  writeStorage(stored)
}

export function clearUserBootstrapProfile(userId: string) {
  const key = userId.trim()
  if (!key) return
  memory.delete(key)
  const stored = readStorage()
  delete stored[key]
  writeStorage(stored)
}

export function clearAllUserBootstrapProfiles() {
  memory.clear()
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
}
