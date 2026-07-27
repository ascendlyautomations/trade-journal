/** Trade room session cache — rooms list, sections, and messages survive route remounts. */

import { isNativeIos } from "@/lib/nativePlatform"
import { persistRoomSession } from "@/lib/nativeSilentCacheBridge"

const DEFAULT_STALE_MS = 5 * 60 * 1000
const STORAGE_PREFIX = "tradetraxs:room-session:v1:"

export type RoomMessagesEntry = {
  pinned: any[]
  main: any[]
  hasOlder?: boolean
}

export type RoomSectionsEntry = {
  list: { id: string; name?: string | null; position?: number | null }[]
  activeSectionId: string | null
}

export type RoomSessionSnapshot = {
  userId: string
  rooms: any[]
  messagesByKey: Record<string, RoomMessagesEntry>
  sectionsByRoom: Record<string, RoomSectionsEntry>
  fetchedAt: number
}

const sessions = new Map<string, RoomSessionSnapshot>()

function storageKey(userId: string): string {
  return `${STORAGE_PREFIX}${userId}`
}

function readStoredSnapshot(userId: string): RoomSessionSnapshot | null {
  if (typeof window === "undefined") return null
  try {
    const raw = window.sessionStorage.getItem(storageKey(userId))
    if (!raw) return null
    const parsed = JSON.parse(raw) as Partial<RoomSessionSnapshot>
    if (
      parsed.userId !== userId ||
      !Array.isArray(parsed.rooms) ||
      typeof parsed.messagesByKey !== "object" ||
      parsed.messagesByKey === null ||
      typeof parsed.sectionsByRoom !== "object" ||
      parsed.sectionsByRoom === null ||
      typeof parsed.fetchedAt !== "number"
    ) {
      window.sessionStorage.removeItem(storageKey(userId))
      return null
    }
    return parsed as RoomSessionSnapshot
  } catch {
    window.sessionStorage.removeItem(storageKey(userId))
    return null
  }
}

function persistSnapshot(snapshot: RoomSessionSnapshot) {
  if (typeof window === "undefined") return
  try {
    window.sessionStorage.setItem(
      storageKey(snapshot.userId),
      JSON.stringify({
        ...snapshot,
        // Web: strip messages to avoid quota. Native keeps messages in IndexedDB.
        messagesByKey: isNativeIos() ? {} : {},
      })
    )
  } catch {
    // Memory caching remains available when session storage is unavailable/full.
  }
  if (isNativeIos()) {
    persistRoomSession(snapshot.userId, snapshot)
  }
}

function emptySnapshot(userId: string): RoomSessionSnapshot {
  return {
    userId,
    rooms: [],
    messagesByKey: {},
    sectionsByRoom: {},
    fetchedAt: Date.now(),
  }
}

export function readRoomSession(userId: string): RoomSessionSnapshot | null {
  const key = userId.trim()
  if (!key) return null
  const entry = sessions.get(key) ?? readStoredSnapshot(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    // Native: still paint soft-stale rooms (SWR). Web: miss.
    if (!(typeof window !== "undefined" && isNativeIos())) {
      sessions.delete(key)
      if (typeof window !== "undefined") {
        window.sessionStorage.removeItem(storageKey(key))
      }
      return null
    }
  }
  sessions.set(key, entry)
  return entry
}

export function writeRoomSession(
  userId: string,
  patch: Partial<
    Pick<
      RoomSessionSnapshot,
      "rooms" | "messagesByKey" | "sectionsByRoom"
    >
  >
) {
  const key = userId.trim()
  if (!key) return
  const prev = sessions.get(key) ?? emptySnapshot(key)
  const next = {
    ...prev,
    ...patch,
    userId: key,
    fetchedAt: Date.now(),
  }
  sessions.set(key, next)
  persistSnapshot(next)
}

export function seedRoomSession(snapshot: RoomSessionSnapshot) {
  if (!snapshot?.userId) return
  const key = String(snapshot.userId).trim()
  const prev = sessions.get(key)
  if (prev && prev.fetchedAt >= snapshot.fetchedAt) return
  sessions.set(key, snapshot)
}

export function patchRoomMessagesInSession(
  userId: string,
  cacheKey: string,
  entry: RoomMessagesEntry
) {
  const key = userId.trim()
  if (!key || !cacheKey) return
  const prev = sessions.get(key) ?? emptySnapshot(key)
  const next = {
    ...prev,
    messagesByKey: { ...prev.messagesByKey, [cacheKey]: entry },
  }
  sessions.set(key, next)
  persistSnapshot(next)
}

export function patchRoomSectionsInSession(
  userId: string,
  roomId: string,
  entry: RoomSectionsEntry
) {
  const key = userId.trim()
  if (!key || !roomId) return
  const prev = sessions.get(key) ?? emptySnapshot(key)
  const next = {
    ...prev,
    sectionsByRoom: { ...prev.sectionsByRoom, [roomId]: entry },
  }
  sessions.set(key, next)
  persistSnapshot(next)
}

export function clearRoomSessionsForUser(userId: string) {
  const key = userId.trim()
  sessions.delete(key)
  if (key && typeof window !== "undefined") {
    window.sessionStorage.removeItem(storageKey(key))
  }
}

export function clearAllRoomSessions() {
  sessions.clear()
  if (typeof window === "undefined") return
  for (let index = window.sessionStorage.length - 1; index >= 0; index -= 1) {
    const key = window.sessionStorage.key(index)
    if (key?.startsWith(STORAGE_PREFIX)) {
      window.sessionStorage.removeItem(key)
    }
  }
}
