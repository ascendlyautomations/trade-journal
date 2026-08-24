import type { SupabaseClient } from "@supabase/supabase-js"
import {
  getCachedTrades,
  isTradesHistoryComplete,
  subscribeAppDataCache,
} from "./appDataCache.ts"
import { countUnreviewedInitialImportsFromTrades } from "./initialImportReviewCountLogic.ts"

export { countUnreviewedInitialImportsFromTrades } from "./initialImportReviewCountLogic.ts"

const COUNT_CACHE_MS = 60_000

type CountEntry = {
  count: number
  fetchedAt: number
  inflight?: Promise<number>
}

const byViewer = new Map<string, CountEntry>()

function countFromCachedTrades(userId: string): number | null {
  const trades = getCachedTrades(userId)
  if (!trades || trades.length === 0) return null
  if (!isTradesHistoryComplete(userId) && trades.length >= 500) {
    return null
  }
  return countUnreviewedInitialImportsFromTrades(trades)
}

async function fetchHeadCount(
  client: SupabaseClient,
  userId: string
): Promise<number> {
  const { count, error } = await client
    .from("trades")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("is_initial_import", true)
    .eq("reviewed", false)

  if (error) {
    console.error("[initialImportReviewCount] head count failed", error)
    return 0
  }
  return count ?? 0
}

export function getCachedInitialImportReviewCount(
  userId: string | null | undefined
): number | null {
  if (!userId?.trim()) return null
  const entry = byViewer.get(userId.trim())
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > COUNT_CACHE_MS) return null
  return entry.count
}

export function patchInitialImportReviewCount(userId: string, count: number) {
  const key = userId.trim()
  if (!key) return
  byViewer.set(key, { count: Math.max(0, count), fetchedAt: Date.now() })
}

export function invalidateInitialImportReviewCount(userId?: string | null) {
  if (!userId?.trim()) {
    byViewer.clear()
    return
  }
  byViewer.delete(userId.trim())
}

/** @internal */
export function resetInitialImportReviewCountForTests() {
  byViewer.clear()
}

export async function ensureInitialImportReviewCountLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<number> {
  const key = userId.trim()
  if (!key) return 0

  if (!options?.force) {
    const cachedCount = getCachedInitialImportReviewCount(key)
    if (cachedCount != null) return cachedCount

    const derived = countFromCachedTrades(key)
    if (derived != null) {
      patchInitialImportReviewCount(key, derived)
      return derived
    }
  }

  const entry = byViewer.get(key)
  if (entry && !options?.force && Date.now() - entry.fetchedAt <= COUNT_CACHE_MS) {
    return entry.count
  }
  if (entry?.inflight) return entry.inflight

  const inflight = fetchHeadCount(client, key).then((count) => {
    byViewer.set(key, { count, fetchedAt: Date.now() })
    return count
  })
  byViewer.set(key, {
    count: entry?.count ?? 0,
    fetchedAt: entry?.fetchedAt ?? 0,
    inflight,
  })
  return inflight
}

export function subscribeInitialImportReviewCountRefresh(
  userId: string,
  onChange: () => void
): () => void {
  return subscribeAppDataCache(() => {
    invalidateInitialImportReviewCount(userId)
    onChange()
  })
}
