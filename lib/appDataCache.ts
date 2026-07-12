import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { DEMO_ACCOUNTS, DEMO_TRADES } from "./demo/fixtures"
import { TRADES_APP_SELECT } from "./publicAccountPrivacy"

/** Shared client-side cache for trades and accounts (module-level, survives route remounts). */

export const ACCOUNTS_SELECT =
  "id, account_number, name, account_size, mode, category, is_active, can_add_trades, note, consistency, max_drawdown, daily_drawdown, profit_target, winning_days, winning_day_threshold" as const

const DEFAULT_STALE_MS = 5 * 60 * 1000

type CacheEntry<T> = {
  userId: string
  data: T
  fetchedAt: number
  invalidated: boolean
  loading: boolean
}

type TradesEntry = CacheEntry<any[]>
type AccountsEntry = CacheEntry<any[]>

const tradesByUser = new Map<string, TradesEntry>()
const accountsByUser = new Map<string, AccountsEntry>()
const listeners = new Set<() => void>()

/** Stable empty snapshots — never allocate new arrays inside getSnapshot(). */
export const EMPTY_TRADES: readonly any[] = Object.freeze([])
export const EMPTY_ACCOUNTS: readonly any[] = Object.freeze([])

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

export function subscribeAppDataCache(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

function isStale(fetchedAt: number, staleMs = DEFAULT_STALE_MS): boolean {
  return Date.now() - fetchedAt > staleMs
}

function tradeIdKey(id: unknown): string {
  return String(id)
}

export function getCachedTrades(userId: string | null | undefined): any[] | null {
  if (!userId) return null
  const entry = tradesByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  if (isStale(entry.fetchedAt)) return null
  return entry.data
}

export function getCachedAccounts(userId: string | null | undefined): any[] | null {
  if (!userId) return null
  const entry = accountsByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  if (isStale(entry.fetchedAt)) return null
  return entry.data
}

/** Stable snapshot for useSyncExternalStore — same reference when data unchanged. */
export function getTradesSnapshot(
  userId: string | null | undefined
): readonly any[] {
  return getCachedTrades(userId) ?? EMPTY_TRADES
}

/** Stable snapshot for useSyncExternalStore — same reference when data unchanged. */
export function getAccountsSnapshot(
  userId: string | null | undefined
): readonly any[] {
  return getCachedAccounts(userId) ?? EMPTY_ACCOUNTS
}

/** Stable boolean snapshot for useSyncExternalStore. */
export function getTradesLoadingSnapshot(
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  if (getCachedTrades(userId)) return false
  return true
}

/** Stable boolean snapshot for useSyncExternalStore. */
export function getAccountsLoadingSnapshot(
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  if (getCachedAccounts(userId)) return false
  return true
}

export function isTradesCacheLoading(userId: string | null | undefined): boolean {
  if (!userId) return false
  return tradesByUser.get(userId)?.loading === true
}

export function isAccountsCacheLoading(userId: string | null | undefined): boolean {
  if (!userId) return false
  return accountsByUser.get(userId)?.loading === true
}

function notifyStreaksInvalidated(userId: string) {
  void import("./userStreaksCache")
    .then(({ invalidateUserStreaksCache }) => invalidateUserStreaksCache(userId))
    .catch(() => {})
}

function notifyTradingReportsInvalidated(userId: string) {
  void import("./tradingReports/tradingReportCache")
    .then(({ invalidateTradingReportsCache }) => invalidateTradingReportsCache(userId))
    .catch(() => {})
}

export function invalidateTradesCache(userId: string) {
  const entry = tradesByUser.get(userId)
  if (!entry || entry.invalidated) {
    notifyStreaksInvalidated(userId)
    notifyTradingReportsInvalidated(userId)
    return
  }
  tradesByUser.set(userId, { ...entry, invalidated: true })
  notify()
  notifyStreaksInvalidated(userId)
  notifyTradingReportsInvalidated(userId)
}

export function invalidateAccountsCache(userId: string) {
  const entry = accountsByUser.get(userId)
  if (!entry || entry.invalidated) return
  accountsByUser.set(userId, { ...entry, invalidated: true })
  notify()
}

export function invalidateAllAppDataForUser(userId: string) {
  invalidateTradesCache(userId)
  invalidateAccountsCache(userId)
}

export function clearAppDataCache() {
  tradesByUser.clear()
  accountsByUser.clear()
  notify()
}

export function setTradesCache(userId: string, trades: any[]) {
  const prev = tradesByUser.get(userId)
  if (
    prev &&
    prev.data === trades &&
    !prev.loading &&
    !prev.invalidated
  ) {
    return
  }
  tradesByUser.set(userId, {
    userId,
    data: trades,
    fetchedAt: Date.now(),
    invalidated: false,
    loading: false,
  })
  notify()
}

export function setAccountsCache(userId: string, accounts: any[]) {
  const prev = accountsByUser.get(userId)
  if (
    prev &&
    prev.data === accounts &&
    !prev.loading &&
    !prev.invalidated
  ) {
    return
  }
  accountsByUser.set(userId, {
    userId,
    data: accounts,
    fetchedAt: Date.now(),
    invalidated: false,
    loading: false,
  })
  notify()
}

export function upsertTradeInCache(userId: string, trade: Record<string, unknown>) {
  const id = tradeIdKey(trade.id)
  if (!id) return

  const entry = tradesByUser.get(userId)
  const current = entry?.data ?? EMPTY_TRADES
  const index = current.findIndex((t) => tradeIdKey(t.id) === id)
  const next =
    index >= 0
      ? current.map((t, i) => (i === index ? { ...t, ...trade } : t))
      : [{ ...trade }, ...current]

  setTradesCache(userId, next)
  notifyStreaksInvalidated(userId)
  notifyTradingReportsInvalidated(userId)
}

export function prependTradeInCache(userId: string, trade: Record<string, unknown>) {
  const id = tradeIdKey(trade.id)
  if (!id) return

  const entry = tradesByUser.get(userId)
  const current = entry?.data ?? EMPTY_TRADES
  if (current.some((t) => tradeIdKey(t.id) === id)) {
    upsertTradeInCache(userId, trade)
    return
  }
  setTradesCache(userId, [{ ...trade }, ...current])
  notifyStreaksInvalidated(userId)
  notifyTradingReportsInvalidated(userId)
}

export function removeTradeFromCache(userId: string, tradeId: string) {
  const entry = tradesByUser.get(userId)
  if (!entry) return
  const id = tradeIdKey(tradeId)
  setTradesCache(
    userId,
    entry.data.filter((t) => tradeIdKey(t.id) !== id)
  )
  notifyStreaksInvalidated(userId)
  notifyTradingReportsInvalidated(userId)
}

export function mergeTradesInCache(userId: string, imported: any[]) {
  const entry = tradesByUser.get(userId)
  const current = entry?.data ?? EMPTY_TRADES
  const byId = new Map(current.map((t) => [tradeIdKey(t.id), t]))
  for (const row of imported) {
    byId.set(tradeIdKey(row.id), { ...byId.get(tradeIdKey(row.id)), ...row })
  }
  const merged = Array.from(byId.values()).sort((a, b) => {
    const aMs = new Date(a.created_at ?? 0).getTime()
    const bMs = new Date(b.created_at ?? 0).getTime()
    return bMs - aMs
  })
  setTradesCache(userId, merged)
}

export function upsertAccountInCache(userId: string, account: Record<string, unknown>) {
  const id = tradeIdKey(account.id)
  if (!id) return

  const entry = accountsByUser.get(userId)
  const current = entry?.data ?? EMPTY_ACCOUNTS
  const index = current.findIndex((a) => tradeIdKey(a.id) === id)
  const next =
    index >= 0
      ? current.map((a, i) => (i === index ? { ...a, ...account } : a))
      : [...current, account]

  setAccountsCache(userId, next)
}

export async function ensureAccountsLoaded(
  supabase: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<any[]> {
  if (isDemoUserId(userId)) {
    const cached = getCachedAccounts(userId)
    if (!cached) setAccountsCache(userId, [...DEMO_ACCOUNTS])
    return getCachedAccounts(userId) ?? [...DEMO_ACCOUNTS]
  }

  const cached = getCachedAccounts(userId)
  const entry = accountsByUser.get(userId)
  if (cached && !options?.force) return cached
  if (entry?.loading) {
    return new Promise((resolve, reject) => {
      const unsub = subscribeAppDataCache(() => {
        const mem = accountsByUser.get(userId)
        if (!mem?.loading) {
          unsub()
          const hit = getCachedAccounts(userId)
          if (hit) {
            resolve(hit)
            return
          }
          if (mem?.invalidated) {
            reject(new Error("Accounts failed to load"))
            return
          }
          resolve((mem?.data ?? EMPTY_ACCOUNTS) as any[])
        }
      })
    })
  }

  const previousData = (entry?.data ?? EMPTY_ACCOUNTS) as any[]
  const wasLoading = entry?.loading === true

  accountsByUser.set(userId, {
    userId,
    data: previousData,
    fetchedAt: entry?.fetchedAt ?? 0,
    invalidated: true,
    loading: true,
  })
  if (!wasLoading) notify()

  const { data, error } = await supabase
    .from("accounts")
    .select(ACCOUNTS_SELECT)
    .eq("user_id", userId)

  if (error) {
    accountsByUser.set(userId, {
      userId,
      data: previousData,
      fetchedAt: entry?.fetchedAt ?? 0,
      invalidated: true,
      loading: false,
    })
    notify()
    throw new Error(error.message)
  }

  const next = data?.length ? data : (EMPTY_ACCOUNTS as any[])
  setAccountsCache(userId, next)
  return next
}

export async function ensureTradesLoaded(
  supabase: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<any[]> {
  if (isDemoUserId(userId)) {
    const cached = getCachedTrades(userId)
    if (!cached) setTradesCache(userId, DEMO_TRADES)
    return getCachedTrades(userId) ?? DEMO_TRADES
  }

  const cached = getCachedTrades(userId)
  const entry = tradesByUser.get(userId)
  if (cached && !options?.force) return cached
  if (entry?.loading) {
    return new Promise((resolve) => {
      const unsub = subscribeAppDataCache(() => {
        const hit = getCachedTrades(userId)
        if (hit && !tradesByUser.get(userId)?.loading) {
          unsub()
          resolve(hit)
        }
      })
    })
  }

  const previousData = (entry?.data ?? EMPTY_TRADES) as any[]
  const wasLoading = entry?.loading === true

  tradesByUser.set(userId, {
    userId,
    data: previousData,
    fetchedAt: entry?.fetchedAt ?? 0,
    invalidated: true,
    loading: true,
  })
  if (!wasLoading) notify()

  const { data } = await supabase
    .from("trades")
    .select(TRADES_APP_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })

  const next = data?.length ? data : (EMPTY_TRADES as any[])
  setTradesCache(userId, next)
  return next
}
