import type { RoomBootstrapV1 } from "./roomContracts.ts"
import { clearRoomBootstrapFlights } from "./roomBootstrapSingleFlight.ts"

const SOFT_STALE_MS = 60_000

type Entry = {
  key: string
  userId: string
  roomId: string
  bootstrap: RoomBootstrapV1
  fetchedAt: number
  source: "rpc" | "legacy" | "cache"
}

type CacheStore = {
  byKey: Map<string, Entry>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.roomBootstrap.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: CacheStore }
  if (!g[GLOBAL_KEY]) g[GLOBAL_KEY] = { byKey: new Map() }
  return g[GLOBAL_KEY]
}

export function roomBootstrapCacheKey(input: {
  userId: string
  roomId: string
  sectionId?: string | null
}): string {
  const section = input.sectionId?.trim() || "auto"
  return `${input.userId}|${input.roomId}|${section}`
}

export function readRoomBootstrapCache(key: string): RoomBootstrapV1 | null {
  return store().byKey.get(key)?.bootstrap ?? null
}

export function readRoomBootstrapCacheEntry(key: string): Entry | null {
  return store().byKey.get(key) ?? null
}

export function isRoomBootstrapCacheSoftStale(key: string): boolean {
  const entry = store().byKey.get(key)
  if (!entry) return true
  return Date.now() - entry.fetchedAt > SOFT_STALE_MS
}

export function writeRoomBootstrapCache(
  key: string,
  userId: string,
  roomId: string,
  bootstrap: RoomBootstrapV1,
  source: Entry["source"] = "rpc"
): void {
  store().byKey.set(key, {
    key,
    userId,
    roomId,
    bootstrap,
    fetchedAt: Date.now(),
    source,
  })
}

export function clearRoomBootstrapCache(userId?: string | null): void {
  if (userId) {
    const s = store()
    for (const [k, entry] of s.byKey) {
      if (entry.userId === userId) s.byKey.delete(k)
    }
    clearRoomBootstrapFlights(userId)
    return
  }
  store().byKey.clear()
  clearRoomBootstrapFlights()
}

export function invalidateRoomBootstrap(
  userId?: string | null,
  roomId?: string | null
): void {
  if (!userId && !roomId) {
    clearRoomBootstrapCache()
    return
  }
  const s = store()
  for (const [k, entry] of s.byKey) {
    if (userId && entry.userId !== userId) continue
    if (roomId && entry.roomId !== roomId) continue
    s.byKey.delete(k)
  }
  if (userId) clearRoomBootstrapFlights(userId)
}
