/**
 * Canonical Feed Bootstrap cache (Symbol.for / globalThis).
 * Keyed by user + scope + content_filter + cursor (first page = empty cursor).
 * Realtime patches UI state — never re-run bootstrap for incremental updates.
 */

import type { FeedBootstrapV1 } from "./contracts.ts"
import { clearFeedBootstrapFlights } from "./feedBootstrapSingleFlight.ts"

type Entry = {
  key: string
  userId: string
  bootstrap: FeedBootstrapV1
  fetchedAt: number
  source: "rpc" | "rest" | "cache"
}

type CacheStore = {
  byKey: Map<string, Entry>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.feedBootstrap.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: CacheStore }
  if (!g[GLOBAL_KEY]) g[GLOBAL_KEY] = { byKey: new Map() }
  return g[GLOBAL_KEY]
}

export function feedBootstrapCacheKey(input: {
  userId: string
  scope: string
  contentFilter: string
  cursor?: string | null
}): string {
  const cursor = input.cursor?.trim() || ""
  return `${input.userId}|${input.scope}|${input.contentFilter}|${cursor}`
}

export function readFeedBootstrapCache(
  key: string
): FeedBootstrapV1 | null {
  return store().byKey.get(key)?.bootstrap ?? null
}

export function writeFeedBootstrapCache(
  key: string,
  userId: string,
  bootstrap: FeedBootstrapV1,
  source: Entry["source"] = "rpc"
): void {
  store().byKey.set(key, {
    key,
    userId,
    bootstrap,
    fetchedAt: Date.now(),
    source,
  })
}

export function clearFeedBootstrapCache(userId?: string | null): void {
  if (userId) {
    const s = store()
    for (const [k, entry] of s.byKey) {
      if (entry.userId === userId) s.byKey.delete(k)
    }
    clearFeedBootstrapFlights(userId)
    return
  }
  store().byKey.clear()
  clearFeedBootstrapFlights()
}

export function invalidateFeedBootstrap(userId?: string | null): void {
  clearFeedBootstrapCache(userId)
}
