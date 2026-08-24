import type { ReelRow } from "./reels.ts"

export const REELS_BY_TRADE_IDS_CACHE_MS = 60_000

type CacheEntry = {
  map: Map<string, ReelRow>
  fetchedAt: number
}

type InflightEntry = {
  promise: Promise<Map<string, ReelRow>>
}

const cacheByKey = new Map<string, CacheEntry>()
const inflightByKey = new Map<string, InflightEntry>()

function normalizeTradeIds(tradeIds: readonly string[]): string[] {
  return [
    ...new Set(
      tradeIds
        .map((id) => (id != null ? String(id).trim() : ""))
        .filter((id) => id !== "")
    ),
  ].sort()
}

export function buildReelsByTradeIdsCacheKey(
  viewerId: string,
  tradeIds: readonly string[]
): string | null {
  const viewer = viewerId.trim()
  if (!viewer) return null
  const ids = normalizeTradeIds(tradeIds)
  if (ids.length === 0) return null
  return `${viewer}:${ids.join(",")}`
}

export function readReelsByTradeIdsCache(
  cacheKey: string
): CacheEntry | null {
  const hit = cacheByKey.get(cacheKey)
  if (!hit) return null
  return hit
}

export function isReelsByTradeIdsCacheFresh(
  entry: CacheEntry,
  now = Date.now()
): boolean {
  return now - entry.fetchedAt <= REELS_BY_TRADE_IDS_CACHE_MS
}

export function writeReelsByTradeIdsCache(
  cacheKey: string,
  map: Map<string, ReelRow>
) {
  cacheByKey.set(cacheKey, {
    map: new Map(map),
    fetchedAt: Date.now(),
  })
}

export function getReelsByTradeIdsInflight(
  cacheKey: string
): Promise<Map<string, ReelRow>> | null {
  return inflightByKey.get(cacheKey)?.promise ?? null
}

export function setReelsByTradeIdsInflight(
  cacheKey: string,
  promise: Promise<Map<string, ReelRow>>
) {
  inflightByKey.set(cacheKey, { promise })
}

export function clearReelsByTradeIdsInflight(cacheKey: string) {
  inflightByKey.delete(cacheKey)
}

export function invalidateReelsByTradeIdsCache(options?: {
  viewerId?: string | null
  tradeIds?: readonly string[]
}) {
  if (!options?.viewerId?.trim()) {
    cacheByKey.clear()
    inflightByKey.clear()
    return
  }

  const viewer = options.viewerId.trim()
  if (options.tradeIds?.length) {
    const key = buildReelsByTradeIdsCacheKey(viewer, options.tradeIds)
    if (key) {
      cacheByKey.delete(key)
      inflightByKey.delete(key)
    }
    return
  }

  for (const key of [...cacheByKey.keys(), ...inflightByKey.keys()]) {
    if (key.startsWith(`${viewer}:`)) {
      cacheByKey.delete(key)
      inflightByKey.delete(key)
    }
  }
}

/** @internal */
export function resetReelsByTradeIdsCacheForTests() {
  cacheByKey.clear()
  inflightByKey.clear()
}
