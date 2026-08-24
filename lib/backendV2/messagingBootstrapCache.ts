/**
 * Canonical Messaging Bootstrap cache (Symbol.for / globalThis).
 * Keyed by user + cursor. Realtime / inbox events patch UI — never re-bootstrap.
 */

import type { MessagesBootstrapV1 } from "./contracts.ts"
import { clearMessagingBootstrapFlights } from "./messagingBootstrapSingleFlight.ts"

type Entry = {
  key: string
  userId: string
  bootstrap: MessagesBootstrapV1
  fetchedAt: number
  source: "rpc" | "rest" | "cache"
}

type CacheStore = {
  byKey: Map<string, Entry>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.messagingBootstrap.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: CacheStore }
  if (!g[GLOBAL_KEY]) g[GLOBAL_KEY] = { byKey: new Map() }
  return g[GLOBAL_KEY]
}

export function messagingBootstrapCacheKey(input: {
  userId: string
  cursor?: string | null
}): string {
  const cursor = input.cursor?.trim() || ""
  return `${input.userId}|${cursor}`
}

export function readMessagingBootstrapCache(
  key: string
): MessagesBootstrapV1 | null {
  return store().byKey.get(key)?.bootstrap ?? null
}

export function writeMessagingBootstrapCache(
  key: string,
  userId: string,
  bootstrap: MessagesBootstrapV1,
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

export function clearMessagingBootstrapCache(userId?: string | null): void {
  if (userId) {
    const s = store()
    for (const [k, entry] of s.byKey) {
      if (entry.userId === userId) s.byKey.delete(k)
    }
    clearMessagingBootstrapFlights(userId)
    return
  }
  store().byKey.clear()
  clearMessagingBootstrapFlights()
}

export function invalidateMessagingBootstrap(userId?: string | null): void {
  clearMessagingBootstrapCache(userId)
}
