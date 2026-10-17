import type { SupabaseClient } from "@supabase/supabase-js"
import { getCachedTrades, subscribeAppDataCache } from "@/lib/appDataCache"

const COUNT_CACHE_MS = 60_000

type CountEntry = {
  count: number
  fetchedAt: number
}

const byViewer = new Map<string, CountEntry>()

export function countPendingBrokerEnrichmentFromTrades(
  trades: { import_source?: unknown; broker_enrichment_status?: unknown }[]
): number {
  return trades.filter(
    (t) =>
      String(t.import_source ?? "") === "tradovate" &&
      t.broker_enrichment_status === "pending"
  ).length
}

function countPendingFromLoadedTrades(userId: string): number | null {
  const trades = getCachedTrades(userId)
  if (!trades || trades.length === 0) return null
  return countPendingBrokerEnrichmentFromTrades(trades)
}

export function invalidateBrokerEnrichmentPendingCount(userId?: string | null) {
  if (!userId?.trim()) {
    byViewer.clear()
    return
  }
  byViewer.delete(userId.trim())
}

export async function ensureBrokerEnrichmentPendingCountLoaded(
  _client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<number> {
  const key = userId.trim()
  if (!key) return 0

  // Owner journal columns are not granted on public.trades. A head count
  // against those columns fails with an empty PostgREST body. The owner
  // trade cache already includes them via the owner read path.
  const derived = countPendingFromLoadedTrades(key)
  if (derived != null) {
    byViewer.set(key, { count: derived, fetchedAt: Date.now() })
    return derived
  }

  const entry = byViewer.get(key)
  if (entry && !options?.force && Date.now() - entry.fetchedAt <= COUNT_CACHE_MS) {
    return entry.count
  }
  return 0
}

export function subscribeBrokerEnrichmentPendingCountRefresh(
  userId: string,
  onChange: () => void
): () => void {
  return subscribeAppDataCache(() => {
    invalidateBrokerEnrichmentPendingCount(userId)
    onChange()
  })
}
