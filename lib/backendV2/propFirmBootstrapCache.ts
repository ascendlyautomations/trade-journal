import type { PropFirmBootstrapV1 } from "./propFirmBootstrapContracts.ts"
import { clearPropFirmBootstrapFlights } from "./propFirmBootstrapSingleFlight.ts"

const SOFT_STALE_MS = 5 * 60 * 1000
const GLOBAL_KEY = Symbol.for("tradetraxs.propFirmBootstrap.cache")

type Entry = {
  userId: string
  bootstrap: PropFirmBootstrapV1
  fetchedAt: number
  source: "rpc" | "rest" | "cache"
}

type CacheStore = {
  entry: Entry | null
  listeners: Set<() => void>
}

function store(): CacheStore {
  const g = globalThis as typeof globalThis & {
    [GLOBAL_KEY]?: CacheStore
  }
  if (!g[GLOBAL_KEY]) {
    g[GLOBAL_KEY] = { entry: null, listeners: new Set() }
  }
  return g[GLOBAL_KEY]
}

function notifyListeners() {
  for (const listener of store().listeners) listener()
}

export function readPropFirmBootstrapCache(
  userId: string | null | undefined
): PropFirmBootstrapV1 | null {
  const entry = store().entry
  if (!userId || !entry || entry.userId !== userId) return null
  return entry.bootstrap
}

export function writePropFirmBootstrapCache(
  userId: string,
  bootstrap: PropFirmBootstrapV1,
  source: Entry["source"] = "rpc"
): void {
  store().entry = { userId, bootstrap, fetchedAt: Date.now(), source }
  notifyListeners()
}

export function isPropFirmBootstrapCacheSoftStale(userId: string): boolean {
  const entry = store().entry
  if (!entry || entry.userId !== userId) return false
  return Date.now() - entry.fetchedAt > SOFT_STALE_MS
}

export function clearPropFirmBootstrapCache(): void {
  store().entry = null
  clearPropFirmBootstrapFlights()
  notifyListeners()
}

export function invalidatePropFirmBootstrap(userId?: string | null): void {
  if (userId) {
    const entry = store().entry
    if (entry?.userId === userId) {
      store().entry = null
      notifyListeners()
    }
    clearPropFirmBootstrapFlights(userId)
    return
  }
  clearPropFirmBootstrapCache()
}
