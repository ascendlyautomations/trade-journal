import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { DEMO_ACCOUNTS, DEMO_TRADES } from "./demo/fixtures"
import {
  TRADES_ANALYTICS_SELECT,
  TRADES_APP_SELECT,
} from "./publicAccountPrivacy"
import { isNativeIos } from "./nativePlatform"
import {
  persistDashboardAccounts,
  persistDashboardTrades,
} from "./nativeSilentCacheBridge"
import { isBackendV2Enabled } from "./backendV2/flags.ts"

/** Shared client-side cache for trades and accounts (module-level, survives route remounts). */

export const ACCOUNTS_SELECT =
  "id, account_number, name, account_size, mode, category, is_active, can_add_trades, note, consistency, max_drawdown, daily_drawdown, profit_target, winning_days, winning_day_threshold" as const

const DEFAULT_STALE_MS = 5 * 60 * 1000
/** Native dashboard soft freshness window (SWR still serves stale). */
const NATIVE_DASHBOARD_SOFT_MS = 45_000

/**
 * Recent window for first interactive paint (auth warm + dashboard stage 1).
 * Full history is loaded only when a screen explicitly requests it.
 */
export const INITIAL_TRADES_LIMIT = 120

type CacheEntry<T> = {
  userId: string
  data: T
  fetchedAt: number
  invalidated: boolean
  loading: boolean
}

type TradesEntry = CacheEntry<any[]> & {
  /**
   * True only when every cached trade row is a full journal row
   * (`TRADES_APP_SELECT`). A complete narrow analytics history must not set this.
   */
  historyComplete: boolean
  /**
   * True when every trade required for Dashboard/Calendar analytics is cached.
   * Independent from `historyComplete`. Full journal history implies this.
   */
  analyticsHistoryComplete: boolean
}
type AccountsEntry = CacheEntry<any[]>

const tradesByUser = new Map<string, TradesEntry>()
const accountsByUser = new Map<string, AccountsEntry>()
const tradesHistoryInFlight = new Map<string, Promise<any[]>>()
const analyticsHistoryInFlight = new Map<string, Promise<any[]>>()
const richRowsByIdInFlight = new Map<string, number>()
const listeners = new Set<() => void>()

type BrokerTradePatch =
  | { op: "upsert"; row: Record<string, unknown> }
  | { op: "delete"; id: string }

/**
 * Patches that arrived while a window or full-history read was in flight.
 * Applied onto the server result so that read cannot drop a just-imported row.
 */
const brokerPatchesByUser = new Map<string, Map<string, BrokerTradePatch>>()

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

function compareTradesNewestFirst(a: { created_at?: string | null; id?: unknown }, b: { created_at?: string | null; id?: unknown }) {
  const aMs = new Date(a.created_at ?? 0).getTime()
  const bMs = new Date(b.created_at ?? 0).getTime()
  if (aMs !== bMs) return bMs - aMs
  const aId = tradeIdKey(a.id)
  const bId = tradeIdKey(b.id)
  if (aId < bId) return -1
  if (aId > bId) return 1
  return 0
}

function waitForTradeWindowIdle(userId: string): Promise<void> {
  if (tradesByUser.get(userId)?.loading !== true) return Promise.resolve()
  return new Promise((resolve) => {
    let settled = false
    const finish = () => {
      if (settled) return
      settled = true
      unsub()
      resolve()
    }
    const unsub = subscribeAppDataCache(() => {
      if (tradesByUser.get(userId)?.loading) return
      finish()
    })
    if (tradesByUser.get(userId)?.loading !== true) finish()
  })
}

function tradeReadInFlight(userId: string): boolean {
  return (
    tradesHistoryInFlight.has(userId) ||
    analyticsHistoryInFlight.has(userId) ||
    (richRowsByIdInFlight.get(userId) ?? 0) > 0 ||
    tradesByUser.get(userId)?.loading === true
  )
}

/** Last in-flight read may consume queued broker patches. `self` is still running. */
function otherTradeReadsInFlight(
  userId: string,
  self: "analytics" | "full" | "ids" | "window"
): boolean {
  const analytics = analyticsHistoryInFlight.has(userId)
  const full = tradesHistoryInFlight.has(userId)
  const idReads = richRowsByIdInFlight.get(userId) ?? 0
  const window = tradesByUser.get(userId)?.loading === true
  if (self === "analytics") return full || idReads > 0 || window
  if (self === "full") return analytics || idReads > 0 || window
  if (self === "ids") return analytics || full || window || idReads > 1
  return analytics || full || idReads > 0
}

export function mergeTradeRowsById(
  existing: readonly any[],
  incoming: readonly any[]
): any[] {
  const byId = new Map(
    existing.map((trade) => [tradeIdKey(trade.id), { ...trade }])
  )
  for (const row of incoming) {
    const id = tradeIdKey(row.id)
    const prev = byId.get(id)
    byId.set(id, prev ? { ...prev, ...row } : { ...row })
  }
  return Array.from(byId.values()).sort(compareTradesNewestFirst)
}

/** Complete snapshot: ids missing from `incoming` are removed. Rich fields on survivors stay. */
export function mergeAnalyticsSnapshot(
  existing: readonly any[],
  incoming: readonly any[]
): any[] {
  const existingById = new Map(
    existing.map((trade) => [tradeIdKey(trade.id), trade])
  )
  return incoming
    .map((row) => {
      const prev = existingById.get(tradeIdKey(row.id))
      return prev ? { ...prev, ...row } : { ...row }
    })
    .sort(compareTradesNewestFirst)
}

/** A complete full-journal cache stays complete unless the snapshot adds an id. */
export function fullJournalRemainsComplete(
  existing: readonly any[],
  incoming: readonly any[],
  wasComplete: boolean
): boolean {
  if (!wasComplete) return false
  const ids = new Set(existing.map((trade) => tradeIdKey(trade.id)))
  return incoming.every((row) => ids.has(tradeIdKey(row.id)))
}

function queueBrokerPatch(userId: string, patch: BrokerTradePatch) {
  const id = patch.op === "delete" ? patch.id : tradeIdKey(patch.row.id)
  if (!id || id === "undefined" || id === "null") return
  let bucket = brokerPatchesByUser.get(userId)
  if (!bucket) {
    bucket = new Map()
    brokerPatchesByUser.set(userId, bucket)
  }
  bucket.set(id, patch.op === "delete" ? patch : { op: "upsert", row: patch.row })
}

function overlayBrokerPatches(userId: string, rows: any[], consume: boolean): any[] {
  const bucket = brokerPatchesByUser.get(userId)
  if (!bucket || bucket.size === 0) return rows
  const byId = new Map(rows.map((trade) => [tradeIdKey(trade.id), { ...trade }]))
  for (const [id, patch] of bucket) {
    if (patch.op === "delete") {
      byId.delete(id)
      continue
    }
    byId.set(id, { ...byId.get(id), ...patch.row })
  }
  if (consume) brokerPatchesByUser.delete(userId)
  return Array.from(byId.values()).sort(compareTradesNewestFirst)
}

function brokerImportSource(row: { import_source?: unknown } | null | undefined): string {
  return String(row?.import_source ?? "")
}

function isBrokerImportSource(source: string): boolean {
  return source === "tradovate" || source === "rithmic"
}

/**
 * Apply one broker-import realtime row to the session trade cache.
 * Does not mark history complete, and does not start a full-journal read.
 * Returns needsWindowLoad when there is no cache yet (caller fetches the 120-row window).
 */
export function applyBrokerImportedTradeToCache(
  userId: string,
  eventType: string,
  nextRow: Record<string, unknown> | null | undefined,
  previousRow?: Record<string, unknown> | null
): { needsWindowLoad: boolean } {
  const isDelete = eventType === "DELETE"
  const sourceRow = isDelete ? previousRow : nextRow
  const id = tradeIdKey(sourceRow?.id)
  if (!userId || !id || id === "undefined" || id === "null") {
    return { needsWindowLoad: false }
  }

  const entry = tradesByUser.get(userId)
  const cachedRow = entry?.data.find((trade) => tradeIdKey(trade.id) === id)
  const payloadSource = brokerImportSource(sourceRow as { import_source?: unknown } | null | undefined)
  const source = isBrokerImportSource(payloadSource)
    ? payloadSource
    : brokerImportSource(cachedRow as { import_source?: unknown } | undefined)
  if (!isBrokerImportSource(source)) {
    return { needsWindowLoad: false }
  }

  const historyInFlight = tradeReadInFlight(userId)
  const windowLoading = entry?.loading === true

  if (isDelete) {
    if (historyInFlight || windowLoading) {
      queueBrokerPatch(userId, { op: "delete", id })
    }
    if (entry && !windowLoading) {
      removeTradeFromCache(userId, id)
    }
    return { needsWindowLoad: false }
  }

  const row = { ...(nextRow as Record<string, unknown>) }
  if (historyInFlight || windowLoading || !entry) {
    queueBrokerPatch(userId, { op: "upsert", row })
  }
  if (!entry) {
    return { needsWindowLoad: true }
  }
  if (windowLoading) {
    return { needsWindowLoad: false }
  }

  const current = entry.data ?? EMPTY_TRADES
  const index = current.findIndex((trade) => tradeIdKey(trade.id) === id)
  const next =
    index >= 0
      ? current.map((trade, i) => (i === index ? { ...trade, ...row } : trade))
      : [...current, row]
  setTradesCache(userId, next.slice().sort(compareTradesNewestFirst))
  notifyStreaksInvalidated(userId)
  notifyTradingReportsInvalidated(userId)
  return { needsWindowLoad: false }
}

export function getCachedTrades(userId: string | null | undefined): any[] | null {
  if (!userId) return null
  const entry = tradesByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  const softMs =
    typeof window !== "undefined" && isNativeIos()
      ? NATIVE_DASHBOARD_SOFT_MS
      : DEFAULT_STALE_MS
  // Native: serve soft-stale for instant paint (SWR). Web: miss when stale.
  if (isStale(entry.fetchedAt, softMs)) {
    if (typeof window !== "undefined" && isNativeIos()) return entry.data
    return null
  }
  return entry.data
}

export function getCachedAccounts(userId: string | null | undefined): any[] | null {
  if (!userId) return null
  const entry = accountsByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  const softMs =
    typeof window !== "undefined" && isNativeIos()
      ? NATIVE_DASHBOARD_SOFT_MS
      : DEFAULT_STALE_MS
  if (isStale(entry.fetchedAt, softMs)) {
    if (typeof window !== "undefined" && isNativeIos()) return entry.data
    return null
  }
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
  tradesHistoryInFlight.clear()
  analyticsHistoryInFlight.clear()
  richRowsByIdInFlight.clear()
  brokerPatchesByUser.clear()
  notify()
}

export function setTradesCache(
  userId: string,
  trades: any[],
  options?: { historyComplete?: boolean; analyticsHistoryComplete?: boolean }
) {
  const prev = tradesByUser.get(userId)
  const historyComplete =
    options?.historyComplete ?? prev?.historyComplete ?? true
  const analyticsHistoryComplete =
    options?.analyticsHistoryComplete ??
    prev?.analyticsHistoryComplete ??
    historyComplete
  if (
    prev &&
    prev.data === trades &&
    !prev.loading &&
    !prev.invalidated &&
    prev.historyComplete === historyComplete &&
    prev.analyticsHistoryComplete === analyticsHistoryComplete
  ) {
    return
  }
  tradesByUser.set(userId, {
    userId,
    data: trades,
    fetchedAt: Date.now(),
    invalidated: false,
    loading: false,
    historyComplete,
    analyticsHistoryComplete:
      historyComplete && options?.analyticsHistoryComplete !== false
        ? true
        : analyticsHistoryComplete,
  })
  persistDashboardTrades(userId, trades)
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
  persistDashboardAccounts(userId, accounts)
  notify()
}

/** Hydrate from IndexedDB without clobbering a fresher in-memory entry. */
export function seedTradesCache(
  userId: string,
  trades: any[],
  fetchedAt: number,
  options?: { historyComplete?: boolean; analyticsHistoryComplete?: boolean }
) {
  if (!userId) return
  const prev = tradesByUser.get(userId)
  if (prev && !prev.invalidated && prev.fetchedAt >= fetchedAt) return
  const historyComplete = options?.historyComplete ?? true
  tradesByUser.set(userId, {
    userId,
    data: trades,
    fetchedAt,
    invalidated: false,
    loading: false,
    historyComplete,
    analyticsHistoryComplete:
      options?.analyticsHistoryComplete ?? historyComplete,
  })
  notify()
}

export function seedAccountsCache(
  userId: string,
  accounts: any[],
  fetchedAt: number
) {
  if (!userId) return
  const prev = accountsByUser.get(userId)
  if (prev && !prev.invalidated && prev.fetchedAt >= fetchedAt) return
  accountsByUser.set(userId, {
    userId,
    data: accounts,
    fetchedAt,
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

  // Dashboard RPC owns accounts when flag ON — one network path.
  if (isBackendV2Enabled("dashboard") && !options?.force) {
    const hit = getCachedAccounts(userId)
    if (hit) return hit
    try {
      const { loadDashboardBootstrapForUser } = await import(
        "./backendV2/dashboardBootstrapRepository.ts"
      )
      await loadDashboardBootstrapForUser(supabase, userId, {
        caller: "ensureAccountsLoaded",
      })
      return getCachedAccounts(userId) ?? []
    } catch (err) {
      console.warn(
        "[appDataCache] dashboard bootstrap accounts failed; REST fallback",
        err
      )
    }
  }

  const cached = getCachedAccounts(userId)
  const entry = accountsByUser.get(userId)
  if (cached && !options?.force) {
    if (
      entry &&
      typeof window !== "undefined" &&
      isNativeIos() &&
      isStale(entry.fetchedAt, NATIVE_DASHBOARD_SOFT_MS)
    ) {
      void ensureAccountsLoaded(supabase, userId, { force: true })
    }
    return cached
  }
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

export function isTradesHistoryComplete(
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  return tradesByUser.get(userId)?.historyComplete === true
}

export function isAnalyticsHistoryComplete(
  userId: string | null | undefined
): boolean {
  if (!userId) return false
  const entry = tradesByUser.get(userId)
  if (!entry) return false
  return entry.analyticsHistoryComplete === true || entry.historyComplete === true
}

/**
 * Full journal history (`TRADES_APP_SELECT`) for Trades, Analyst, and any
 * surface that needs notes, screenshots, or other journal fields.
 * Does not flip `loading`. A complete analytics history does not satisfy this.
 *
 * Auth warm / generic prefetch must NOT call this — only explicit consumers.
 */
export async function ensureFullTradesHistory(
  supabase: SupabaseClient,
  userId: string
): Promise<any[]> {
  if (isDemoUserId(userId)) {
    const cached = getCachedTrades(userId)
    if (!cached) {
      setTradesCache(userId, DEMO_TRADES, {
        historyComplete: true,
        analyticsHistoryComplete: true,
      })
    }
    return getCachedTrades(userId) ?? DEMO_TRADES
  }

  const entry = tradesByUser.get(userId)
  if (entry && !entry.invalidated && entry.historyComplete && !entry.loading) {
    return entry.data
  }

  const existing = tradesHistoryInFlight.get(userId)
  if (existing) return existing

  const promise = (async () => {
    const { data, error } = await supabase
      .from("trades")
      .select(TRADES_APP_SELECT)
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    if (error) {
      // Leave the recent window in place; next ensureTradesLoaded can retry.
      return getCachedTrades(userId) ?? (EMPTY_TRADES as any[])
    }

    const fetched = data?.length ? data : (EMPTY_TRADES as any[])
    const current = tradesByUser.get(userId)?.data ?? []
    const merged = mergeAnalyticsSnapshot(current, fetched)
    const next = overlayBrokerPatches(
      userId,
      merged,
      !otherTradeReadsInFlight(userId, "full")
    )
    setTradesCache(userId, next, {
      historyComplete: true,
      analyticsHistoryComplete: true,
    })
    return next
  })().finally(() => {
    tradesHistoryInFlight.delete(userId)
  })

  tradesHistoryInFlight.set(userId, promise)
  return promise
}

/**
 * Every trade, narrow analytics columns only.
 * Merges by id so an existing rich row keeps notes, screenshots, and other
 * fields this projection does not return.
 */
export async function ensureAnalyticsTradesHistory(
  supabase: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<any[]> {
  if (isDemoUserId(userId)) {
    const cached = getCachedTrades(userId)
    if (!cached) {
      setTradesCache(userId, DEMO_TRADES, {
        historyComplete: true,
        analyticsHistoryComplete: true,
      })
    }
    return getCachedTrades(userId) ?? DEMO_TRADES
  }

  const entry = tradesByUser.get(userId)
  if (
    !options?.force &&
    entry &&
    !entry.invalidated &&
    (entry.analyticsHistoryComplete || entry.historyComplete) &&
    !entry.loading
  ) {
    return entry.data
  }

  const existing = analyticsHistoryInFlight.get(userId)
  if (existing) return existing

  const promise = (async () => {
    const { data, error } = await supabase
      .from("trades")
      .select(TRADES_ANALYTICS_SELECT)
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    if (error) {
      return getCachedTrades(userId) ?? (EMPTY_TRADES as any[])
    }

    const fetched = data?.length ? data : (EMPTY_TRADES as any[])
    const currentEntry = tradesByUser.get(userId)
    const current = currentEntry?.data ?? []
    const merged = mergeAnalyticsSnapshot(current, fetched)
    const next = overlayBrokerPatches(
      userId,
      merged,
      !otherTradeReadsInFlight(userId, "analytics")
    )
    const historyComplete = fullJournalRemainsComplete(
      current,
      fetched,
      currentEntry?.historyComplete === true
    )
    setTradesCache(userId, next, {
      historyComplete,
      analyticsHistoryComplete: true,
    })
    return next
  })().finally(() => {
    analyticsHistoryInFlight.delete(userId)
  })

  analyticsHistoryInFlight.set(userId, promise)
  return promise
}

function tradeHasJournalProjection(trade: { notes?: unknown; image_url?: unknown; psychology_notes?: unknown }): boolean {
  return (
    trade != null &&
    ("notes" in trade || "image_url" in trade || "psychology_notes" in trade)
  )
}

/**
 * One batched full-journal read for specific ids (a selected calendar day or
 * a handful of recent cards). Does not mark the full journal complete.
 */
export async function ensureRichTradeRowsByIds(
  supabase: SupabaseClient,
  userId: string,
  ids: readonly string[]
): Promise<void> {
  if (!userId || isDemoUserId(userId)) return
  const unique = [...new Set(ids.map((id) => String(id)).filter((id) => id && id !== "undefined"))]
  if (unique.length === 0) return

  const entry = tradesByUser.get(userId)
  const missing = unique.filter((id) => {
    const row = entry?.data.find((trade) => tradeIdKey(trade.id) === id)
    return !row || !tradeHasJournalProjection(row)
  })
  if (missing.length === 0) return

  richRowsByIdInFlight.set(userId, (richRowsByIdInFlight.get(userId) ?? 0) + 1)
  try {
    const chunkSize = 100
    const richRows: any[] = []
    for (let i = 0; i < missing.length; i += chunkSize) {
      const chunk = missing.slice(i, i + chunkSize)
      const { data, error } = await supabase
        .from("trades")
        .select(TRADES_APP_SELECT)
        .in("id", chunk)
      if (error || !data?.length) continue
      richRows.push(...data)
    }
    const latest = tradesByUser.get(userId)
    const merged = mergeTradeRowsById(latest?.data ?? [], richRows)
    const next = overlayBrokerPatches(
      userId,
      merged,
      !otherTradeReadsInFlight(userId, "ids")
    )
    setTradesCache(userId, next, {
      historyComplete: latest?.historyComplete ?? false,
      analyticsHistoryComplete: latest?.analyticsHistoryComplete ?? false,
    })
  } finally {
    const left = (richRowsByIdInFlight.get(userId) ?? 1) - 1
    if (left <= 0) richRowsByIdInFlight.delete(userId)
    else richRowsByIdInFlight.set(userId, left)
  }
}

export type EnsureTradesLoadedOptions = {
  force?: boolean
  isRetry?: boolean
  /**
   * When true, also load full journal history after the recent window.
   * Default false — auth warm and unrelated screens stay on the 120-trade window.
   * Independent from `analyticsHistory`. Narrow analytics completeness does not
   * satisfy this.
   */
  fullHistory?: boolean
  /**
   * When true, load every trade with the narrow analytics projection after the
   * recent rich window. Does not download the full journal.
   * Ignored when `fullHistory` is also set — the journal select is a superset.
   */
  analyticsHistory?: boolean
}

export async function ensureTradesLoaded(
  supabase: SupabaseClient,
  userId: string,
  options?: EnsureTradesLoadedOptions
): Promise<any[]> {
  if (isDemoUserId(userId)) {
    const cached = getCachedTrades(userId)
    if (!cached) {
      setTradesCache(userId, DEMO_TRADES, {
        historyComplete: true,
        analyticsHistoryComplete: true,
      })
    }
    return getCachedTrades(userId) ?? DEMO_TRADES
  }

  const wantFullHistory = options?.fullHistory === true
  const wantAnalyticsHistory =
    options?.analyticsHistory === true && !wantFullHistory
  let entry = tradesByUser.get(userId)

  // A weaker in-flight read must not satisfy a stronger caller.
  // Window < analytics history < full journal.
  if (entry?.loading) {
    await waitForTradeWindowIdle(userId)
    const afterWindow = tradesByUser.get(userId)
    if (!afterWindow || afterWindow.invalidated) {
      return (afterWindow?.data ?? EMPTY_TRADES) as any[]
    }
    return ensureTradesLoaded(supabase, userId, options)
  }

  if (!options?.force && tradesHistoryInFlight.has(userId)) {
    const fullTask = tradesHistoryInFlight.get(userId)!
    if (!wantFullHistory && !wantAnalyticsHistory) {
      const ready = tradesByUser.get(userId)
      if (ready?.data) return ready.data
    }
    await fullTask
    return ensureTradesLoaded(supabase, userId, options)
  }

  if (!options?.force && analyticsHistoryInFlight.has(userId)) {
    const analyticsTask = analyticsHistoryInFlight.get(userId)!
    if (wantFullHistory) {
      await analyticsTask
      return ensureTradesLoaded(supabase, userId, options)
    }
    if (wantAnalyticsHistory) return analyticsTask
    const ready = tradesByUser.get(userId)
    if (ready?.data) return ready.data
  }

  const cached = getCachedTrades(userId)
  entry = tradesByUser.get(userId)

  // Dashboard RPC owns trade window when flag ON — one network path.
  if (isBackendV2Enabled("dashboard") && !options?.force) {
    if (!cached) {
      try {
        const { loadDashboardBootstrapForUser } = await import(
          "./backendV2/dashboardBootstrapRepository.ts"
        )
        await loadDashboardBootstrapForUser(supabase, userId, {
          caller: "ensureTradesLoaded",
        })
      } catch (err) {
        console.warn(
          "[appDataCache] dashboard bootstrap trades failed; REST fallback",
          err
        )
      }
    }
    const after = getCachedTrades(userId)
    const afterEntry = tradesByUser.get(userId)
    if (after) {
      if (wantFullHistory && !afterEntry?.historyComplete) {
        void ensureFullTradesHistory(supabase, userId)
      } else if (
        wantAnalyticsHistory &&
        !afterEntry?.analyticsHistoryComplete &&
        !afterEntry?.historyComplete
      ) {
        void ensureAnalyticsTradesHistory(supabase, userId)
      }
      return after
    }
  }

  if (cached && !options?.force) {
    if (
      entry &&
      typeof window !== "undefined" &&
      isNativeIos() &&
      isStale(entry.fetchedAt, NATIVE_DASHBOARD_SOFT_MS)
    ) {
      void ensureTradesLoaded(supabase, userId, {
        force: true,
        fullHistory: wantFullHistory,
        analyticsHistory: wantAnalyticsHistory,
      })
    }
    // Recent window is enough for warm/prefetch. A caller that asked for a
    // stronger history waits for that read instead of returning the window.
    if (wantFullHistory && !entry?.historyComplete) {
      return ensureFullTradesHistory(supabase, userId)
    }
    if (
      wantAnalyticsHistory &&
      !entry?.analyticsHistoryComplete &&
      !entry?.historyComplete
    ) {
      return ensureAnalyticsTradesHistory(supabase, userId)
    }
    return cached
  }

  const previousData = (entry?.data ?? EMPTY_TRADES) as any[]
  const previousHistoryComplete = entry?.historyComplete ?? false
  const previousAnalyticsComplete = entry?.analyticsHistoryComplete ?? false
  const wasLoading = entry?.loading === true

  tradesByUser.set(userId, {
    userId,
    data: previousData,
    fetchedAt: entry?.fetchedAt ?? 0,
    invalidated: true,
    loading: true,
    historyComplete: previousHistoryComplete,
    analyticsHistoryComplete: previousAnalyticsComplete,
  })
  if (!wasLoading) notify()

  // Stage 1: recent trades only — UI becomes interactive sooner.
  const { data, error } = await supabase
    .from("trades")
    .select(TRADES_APP_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(INITIAL_TRADES_LIMIT)

  // A failed fetch must never be cached as a valid empty history — that makes
  // a trade-owning user look like a 0-trade user (false empty dashboard).
  if (error) {
    tradesByUser.set(userId, {
      userId,
      data: previousData,
      fetchedAt: entry?.fetchedAt ?? 0,
      invalidated: true,
      loading: false,
      historyComplete: previousHistoryComplete,
      analyticsHistoryComplete: previousAnalyticsComplete,
    })
    notify()
    // One delayed retry recovers transient startup failures (token refresh).
    if (!options?.isRetry) {
      setTimeout(() => {
        void ensureTradesLoaded(supabase, userId, {
          isRetry: true,
          fullHistory: wantFullHistory,
          analyticsHistory: wantAnalyticsHistory,
        })
      }, 4000)
    }
    return previousData
  }

  const fetched = data?.length ? data : (EMPTY_TRADES as any[])
  const windowCoversAll = fetched.length < INITIAL_TRADES_LIMIT
  const willFetchFull = wantFullHistory && !windowCoversAll
  const analyticsAlready =
    previousAnalyticsComplete || previousHistoryComplete
  const shouldFetchAnalytics =
    wantAnalyticsHistory &&
    !windowCoversAll &&
    (options?.force === true || !analyticsAlready)
  const willContinue = willFetchFull || shouldFetchAnalytics
  const windowRows = windowCoversAll
    ? mergeAnalyticsSnapshot(previousData, fetched)
    : mergeTradeRowsById(previousData, fetched)
  const next = overlayBrokerPatches(
    userId,
    windowRows,
    !willContinue && !otherTradeReadsInFlight(userId, "window")
  )
  setTradesCache(userId, next, {
    historyComplete: windowCoversAll ? true : previousHistoryComplete,
    analyticsHistoryComplete: windowCoversAll ? true : analyticsAlready,
  })

  // Stage 2: full journal, or narrow analytics. Never both.
  // Explicit refresh waits for that history. First paint does not.
  if (willFetchFull) {
    const fullTask = ensureFullTradesHistory(supabase, userId)
    if (options?.force) await fullTask
    else void fullTask
  } else if (shouldFetchAnalytics) {
    const analyticsTask = ensureAnalyticsTradesHistory(supabase, userId, {
      force: options?.force === true,
    })
    if (options?.force) await analyticsTask
    else void analyticsTask
  }

  return next
}
