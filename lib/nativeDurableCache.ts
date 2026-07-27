/**
 * Native iOS only: durable IndexedDB store for silent offline / SWR caching.
 * Never stores auth tokens or credentials.
 */

import { isNativeIos } from "@/lib/nativePlatform"

const DB_NAME = "tt_native_cache_v1"
const DB_VERSION = 1
const STORE = "entries"

export type DurableCacheEntry<T = unknown> = {
  key: string
  userId: string
  namespace: string
  value: T
  fetchedAt: number
  /** Soft TTL — stale entries may still be painted (SWR). */
  softExpiresAt: number
}

let dbPromise: Promise<IDBDatabase> | null = null

function canUseDurableCache(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof indexedDB !== "undefined" &&
    isNativeIos()
  )
}

function openDb(): Promise<IDBDatabase> {
  if (!canUseDurableCache()) {
    return Promise.reject(new Error("durable_cache_unavailable"))
  }
  if (dbPromise) return dbPromise

  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onerror = () => {
      dbPromise = null
      reject(req.error ?? new Error("idb_open_failed"))
    }
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) {
        const store = db.createObjectStore(STORE, { keyPath: "key" })
        store.createIndex("userId", "userId", { unique: false })
        store.createIndex("namespace", "namespace", { unique: false })
      }
    }
    req.onsuccess = () => resolve(req.result)
  })

  return dbPromise
}

export function durableCacheKey(
  namespace: string,
  userId: string,
  entityKey = "_"
): string {
  return `${namespace}:${userId}:${entityKey}`
}

export async function durableCacheSet<T>(params: {
  namespace: string
  userId: string
  entityKey?: string
  value: T
  softTtlMs: number
  fetchedAt?: number
}): Promise<void> {
  if (!canUseDurableCache()) return
  const userId = params.userId.trim()
  if (!userId) return

  const fetchedAt = params.fetchedAt ?? Date.now()
  const entry: DurableCacheEntry<T> = {
    key: durableCacheKey(params.namespace, userId, params.entityKey ?? "_"),
    userId,
    namespace: params.namespace,
    value: params.value,
    fetchedAt,
    softExpiresAt: fetchedAt + Math.max(0, params.softTtlMs),
  }

  try {
    const db = await openDb()
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite")
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
      tx.objectStore(STORE).put(entry)
    })
  } catch {
    // Quota / private mode — memory caches still work.
  }
}

export async function durableCacheGet<T>(params: {
  namespace: string
  userId: string
  entityKey?: string
}): Promise<DurableCacheEntry<T> | null> {
  if (!canUseDurableCache()) return null
  const userId = params.userId.trim()
  if (!userId) return null

  try {
    const db = await openDb()
    const key = durableCacheKey(params.namespace, userId, params.entityKey ?? "_")
    return await new Promise<DurableCacheEntry<T> | null>((resolve, reject) => {
      const tx = db.transaction(STORE, "readonly")
      const req = tx.objectStore(STORE).get(key)
      req.onsuccess = () => {
        const row = req.result as DurableCacheEntry<T> | undefined
        resolve(row ?? null)
      }
      req.onerror = () => reject(req.error)
    })
  } catch {
    return null
  }
}

export async function durableCacheGetAllForUser(
  userId: string
): Promise<DurableCacheEntry[]> {
  if (!canUseDurableCache()) return []
  const uid = userId.trim()
  if (!uid) return []

  try {
    const db = await openDb()
    return await new Promise<DurableCacheEntry[]>((resolve, reject) => {
      const tx = db.transaction(STORE, "readonly")
      const index = tx.objectStore(STORE).index("userId")
      const req = index.getAll(uid)
      req.onsuccess = () => resolve((req.result as DurableCacheEntry[]) ?? [])
      req.onerror = () => reject(req.error)
    })
  } catch {
    return []
  }
}

export async function durableCacheDeleteUser(userId: string): Promise<void> {
  if (!canUseDurableCache()) return
  const uid = userId.trim()
  if (!uid) return

  try {
    const db = await openDb()
    const rows = await durableCacheGetAllForUser(uid)
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite")
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
      const store = tx.objectStore(STORE)
      for (const row of rows) store.delete(row.key)
    })
  } catch {
    /* ignore */
  }
}

export async function durableCacheClearAll(): Promise<void> {
  if (!canUseDurableCache()) return
  try {
    const db = await openDb()
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite")
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
      tx.objectStore(STORE).clear()
    })
  } catch {
    /* ignore */
  }
}

/** True when entry is past soft TTL but still usable for instant paint. */
export function isDurableEntrySoftExpired(entry: DurableCacheEntry): boolean {
  return Date.now() > entry.softExpiresAt
}
