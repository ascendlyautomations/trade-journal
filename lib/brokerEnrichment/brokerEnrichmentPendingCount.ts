import type { SupabaseClient } from "@supabase/supabase-js"
import {
  getCachedTrades,
  isTradesHistoryComplete,
  subscribeAppDataCache,
} from "@/lib/appDataCache"

const COUNT_CACHE_MS = 60_000

type CountEntry = {
  count: number
  fetchedAt: number
  inflight?: Promise<number>
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

function countFromCachedTrades(userId: string): number | null {
  const trades = getCachedTrades(userId)
  if (!trades || trades.length === 0) return null
  if (!isTradesHistoryComplete(userId) && trades.length >= 500) {
    return null
  }
  return countPendingBrokerEnrichmentFromTrades(trades)
}

async function fetchHeadCount(
  client: SupabaseClient,
  userId: string
): Promise<number> {
  const { count, error } = await client
    .from("trades")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("import_source", "tradovate")
    .eq("broker_enrichment_status", "pending")

  if (error) {
    console.error("[brokerEnrichmentPendingCount] head count failed", error)
    return 0
  }
  return count ?? 0
}

export function invalidateBrokerEnrichmentPendingCount(userId?: string | null) {
  if (!userId?.trim()) {
    byViewer.clear()
    return
  }
  byViewer.delete(userId.trim())
}

export async function ensureBrokerEnrichmentPendingCountLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<number> {
  const key = userId.trim()
  if (!key) return 0

  if (!options?.force) {
    const derived = countFromCachedTrades(key)
    if (derived != null) {
      byViewer.set(key, { count: derived, fetchedAt: Date.now() })
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

export function subscribeBrokerEnrichmentPendingCountRefresh(
  userId: string,
  onChange: () => void
): () => void {
  return subscribeAppDataCache(() => {
    invalidateBrokerEnrichmentPendingCount(userId)
    onChange()
  })
}
