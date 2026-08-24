import type { ConversationThreadBootstrapV1 } from "./conversationThreadContracts.ts"
import { clearConversationThreadFlights } from "./conversationThreadBootstrapSingleFlight.ts"

const SOFT_STALE_MS = 60_000
const MAX_ENTRIES = 24

type Entry = {
  key: string
  userId: string
  conversationId: string
  bootstrap: ConversationThreadBootstrapV1
  fetchedAt: number
  source: "rpc" | "legacy" | "cache"
  nextMessageCursor: string | null
}

type CacheStore = {
  byKey: Map<string, Entry>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.conversationThread.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: CacheStore }
  if (!g[GLOBAL_KEY]) g[GLOBAL_KEY] = { byKey: new Map() }
  return g[GLOBAL_KEY]
}

export function conversationThreadCacheKey(input: {
  userId: string
  conversationId: string
}): string {
  return `${input.userId}|${input.conversationId}`
}

export function readConversationThreadCache(
  key: string
): ConversationThreadBootstrapV1 | null {
  return store().byKey.get(key)?.bootstrap ?? null
}

export function readConversationThreadCacheEntry(key: string): Entry | null {
  return store().byKey.get(key) ?? null
}

export function readConversationThreadPaginationCursor(
  key: string
): string | null {
  return store().byKey.get(key)?.nextMessageCursor ?? null
}

export function isConversationThreadCacheSoftStale(key: string): boolean {
  const entry = store().byKey.get(key)
  if (!entry) return true
  return Date.now() - entry.fetchedAt > SOFT_STALE_MS
}

function trimCacheIfNeeded(): void {
  const s = store()
  if (s.byKey.size <= MAX_ENTRIES) return
  const sorted = [...s.byKey.entries()].sort(
    (a, b) => a[1].fetchedAt - b[1].fetchedAt
  )
  const removeCount = s.byKey.size - MAX_ENTRIES
  for (let i = 0; i < removeCount; i += 1) {
    s.byKey.delete(sorted[i]![0])
  }
}

export function writeConversationThreadCache(
  key: string,
  userId: string,
  conversationId: string,
  bootstrap: ConversationThreadBootstrapV1,
  source: Entry["source"] = "rpc"
): void {
  store().byKey.set(key, {
    key,
    userId,
    conversationId,
    bootstrap,
    fetchedAt: Date.now(),
    source,
    nextMessageCursor: bootstrap.data.next_message_cursor,
  })
  trimCacheIfNeeded()
}

export function patchConversationThreadMessages(
  key: string,
  messages: ConversationThreadBootstrapV1["data"]["messages"],
  hasMore: boolean,
  nextCursor: string | null
): void {
  const entry = store().byKey.get(key)
  if (!entry) return
  entry.bootstrap = {
    ...entry.bootstrap,
    data: {
      ...entry.bootstrap.data,
      messages,
      has_more_messages: hasMore,
      next_message_cursor: nextCursor,
    },
  }
  entry.nextMessageCursor = nextCursor
  entry.fetchedAt = Date.now()
}

export function clearConversationThreadCache(userId?: string | null): void {
  if (userId) {
    const s = store()
    for (const [k, entry] of s.byKey) {
      if (entry.userId === userId) s.byKey.delete(k)
    }
    clearConversationThreadFlights(userId)
    return
  }
  store().byKey.clear()
  clearConversationThreadFlights()
}

export function invalidateConversationThread(
  userId?: string | null,
  conversationId?: string | null
): void {
  if (!userId && !conversationId) {
    clearConversationThreadCache()
    return
  }
  const s = store()
  for (const [k, entry] of s.byKey) {
    if (userId && entry.userId !== userId) continue
    if (conversationId && entry.conversationId !== conversationId) continue
    s.byKey.delete(k)
  }
  if (userId) clearConversationThreadFlights(userId)
}
