/** Trade room session cache — rooms list, sections, and messages survive route remounts. */

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type RoomMessagesEntry = {
  pinned: any[]
  main: any[]
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
  const entry = sessions.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    sessions.delete(key)
    return null
  }
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
  sessions.set(key, {
    ...prev,
    ...patch,
    userId: key,
    fetchedAt: Date.now(),
  })
}

export function patchRoomMessagesInSession(
  userId: string,
  cacheKey: string,
  entry: RoomMessagesEntry
) {
  const key = userId.trim()
  if (!key || !cacheKey) return
  const prev = sessions.get(key) ?? emptySnapshot(key)
  sessions.set(key, {
    ...prev,
    messagesByKey: { ...prev.messagesByKey, [cacheKey]: entry },
    fetchedAt: Date.now(),
  })
}

export function patchRoomSectionsInSession(
  userId: string,
  roomId: string,
  entry: RoomSectionsEntry
) {
  const key = userId.trim()
  if (!key || !roomId) return
  const prev = sessions.get(key) ?? emptySnapshot(key)
  sessions.set(key, {
    ...prev,
    sectionsByRoom: { ...prev.sectionsByRoom, [roomId]: entry },
    fetchedAt: Date.now(),
  })
}

export function clearRoomSessionsForUser(userId: string) {
  sessions.delete(userId.trim())
}

export function clearAllRoomSessions() {
  sessions.clear()
}
