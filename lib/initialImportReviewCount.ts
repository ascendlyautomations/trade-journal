import type { SupabaseClient } from "@supabase/supabase-js"
import {
  getCachedTrades,
  isTradesHistoryComplete,
  subscribeAppDataCache,
} from "./appDataCache.ts"
import { isDemoUserId } from "./demo/constants.ts"
import { DEMO_TRADES } from "./demo/fixtures.ts"
import { countUnreviewedInitialImportsFromTrades } from "./initialImportReviewCountLogic.ts"
import { rpcTradesOwnerRows } from "./tradeOwnerRead.ts"

export { countUnreviewedInitialImportsFromTrades } from "./initialImportReviewCountLogic.ts"

const COUNT_CACHE_MS = 60_000

type CountEntry = {
  count: number
  fetchedAt: number
  inflight?: Promise<number | null>
}

const byViewer = new Map<string, CountEntry>()

function tradesIncludeImportReviewFields(
  trades: readonly unknown[] | null | undefined
): boolean {
  if (!trades?.length) return true
  for (const trade of trades) {
    if (trade && typeof trade === "object") {
      return "is_initial_import" in trade && "reviewed" in trade
    }
  }
  return false
}

function countFromCachedTrades(userId: string): number | null {
  const trades = getCachedTrades(userId)
  if (!trades || trades.length === 0) return null
  if (!tradesIncludeImportReviewFields(trades)) return null
  if (!isTradesHistoryComplete(userId) && trades.length >= 500) {
    return null
  }
  return countUnreviewedInitialImportsFromTrades(trades)
}

async function waitForAuthSession(
  client: SupabaseClient,
  attempts = 2
): Promise<boolean> {
  for (let i = 0; i < attempts; i += 1) {
    const { data } = await client.auth.getSession()
    if (data.session?.access_token) return true
    if (i + 1 < attempts) {
      await new Promise((resolve) => setTimeout(resolve, 350))
    }
  }
  return false
}

/**
 * Owner import-review count via `rpc_v1_trades_owner_rows`.
 * Direct PostgREST filters on `is_initial_import` / `reviewed` fail for
 * authenticated clients — those journal columns are not granted on public.trades
 * (see trades_authenticated_journal_privacy migration).
 */
async function fetchReviewCountFromOwnerRpc(
  client: SupabaseClient,
  userId: string
): Promise<number | null> {
  if (isDemoUserId(userId)) {
    return countUnreviewedInitialImportsFromTrades(DEMO_TRADES)
  }

  const hasSession = await waitForAuthSession(client)
  if (!hasSession) {
    return null
  }

  const { rows, error } = await rpcTradesOwnerRows(client)
  if (error) {
    const message = error.message?.trim()
    if (process.env.NODE_ENV === "development") {
      console.warn(
        "[initialImportReviewCount] owner rows count failed",
        message || error.name || "unknown error"
      )
    }
    return null
  }

  return countUnreviewedInitialImportsFromTrades(rows)
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

/**
 * Returns a non-negative count when known, or `null` when the count could not be
 * loaded (session not ready, network/RPC error). Callers should not treat `null`
 * as zero pending imports.
 */
export async function ensureInitialImportReviewCountLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<number | null> {
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

  const inflight = fetchReviewCountFromOwnerRpc(client, key).then((count) => {
    const previous = byViewer.get(key)
    if (count == null) {
      if (previous && previous.fetchedAt > 0) {
        byViewer.set(key, {
          count: previous.count,
          fetchedAt: previous.fetchedAt,
        })
      } else {
        byViewer.delete(key)
      }
      return null
    }
    byViewer.set(key, { count, fetchedAt: Date.now() })
    return count
  })

  byViewer.set(key, {
    count: entry?.count ?? 0,
    fetchedAt: entry?.fetchedAt ?? 0,
    inflight,
  })

  void inflight.finally(() => {
    const current = byViewer.get(key)
    if (current?.inflight === inflight) {
      byViewer.set(key, {
        count: current.count,
        fetchedAt: current.fetchedAt,
      })
    }
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
