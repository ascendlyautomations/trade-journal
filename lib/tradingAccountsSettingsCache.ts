import type { SupabaseClient } from "@supabase/supabase-js"
import {
  loadTradingAccounts,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"

/** Full trading-account rows for Settings — separate from dashboard ACCOUNTS_SELECT cache. */

const STORAGE_KEY = "tj_trading_accounts_settings_v1"
const DEFAULT_STALE_MS = 5 * 60 * 1000

type AccountsEntry = {
  userId: string
  accounts: TradingAccountListItem[]
  fetchedAt: number
  invalidated: boolean
  loading: boolean
}

const memory = new Map<string, AccountsEntry>()
const listeners = new Set<() => void>()

function readStorage(): Record<string, AccountsEntry> {
  if (typeof window === "undefined") return {}
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, AccountsEntry>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

function writeStorage(entries: Record<string, AccountsEntry>) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
  } catch {
    // ignore
  }
}

function isFresh(fetchedAt: number, staleMs = DEFAULT_STALE_MS): boolean {
  return Date.now() - fetchedAt <= staleMs
}

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

export function subscribeTradingAccountsSettingsCache(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getCachedTradingAccountsSettings(
  userId: string | null | undefined
): TradingAccountListItem[] | null {
  if (!userId) return null
  const key = userId.trim()

  const mem = memory.get(key)
  if (mem && !mem.invalidated && !mem.loading && isFresh(mem.fetchedAt)) {
    return mem.accounts
  }

  const stored = readStorage()[key]
  if (stored && !stored.invalidated && isFresh(stored.fetchedAt)) {
    memory.set(key, { ...stored, loading: false })
    return stored.accounts
  }

  return null
}

export function writeTradingAccountsSettingsCache(
  userId: string,
  accounts: TradingAccountListItem[]
) {
  const key = userId.trim()
  if (!key) return

  const entry: AccountsEntry = {
    userId: key,
    accounts,
    fetchedAt: Date.now(),
    invalidated: false,
    loading: false,
  }
  memory.set(key, entry)

  const stored = readStorage()
  stored[key] = entry
  writeStorage(stored)
  notify()
}

export function invalidateTradingAccountsSettingsCache(userId: string) {
  const key = userId.trim()
  if (!key) return

  const mem = memory.get(key)
  if (mem) {
    memory.set(key, { ...mem, invalidated: true })
  }

  const stored = readStorage()
  if (stored[key]) {
    stored[key] = { ...stored[key], invalidated: true }
    writeStorage(stored)
  }
  notify()
}

export function clearAllTradingAccountsSettingsCaches() {
  memory.clear()
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
  notify()
}

export async function ensureTradingAccountsSettingsLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<TradingAccountListItem[]> {
  const key = userId.trim()
  if (!key) return []

  const cached = getCachedTradingAccountsSettings(key)
  const entry = memory.get(key)
  if (cached && !options?.force) return cached

  if (entry?.loading) {
    return new Promise((resolve) => {
      const unsub = subscribeTradingAccountsSettingsCache(() => {
        const hit = getCachedTradingAccountsSettings(key)
        if (hit && !memory.get(key)?.loading) {
          unsub()
          resolve(hit)
        }
      })
    })
  }

  memory.set(key, {
    userId: key,
    accounts: entry?.accounts ?? cached ?? [],
    fetchedAt: entry?.fetchedAt ?? 0,
    invalidated: true,
    loading: true,
  })
  notify()

  const { accounts, error } = await loadTradingAccounts(client, key)
  if (error) {
    memory.set(key, {
      userId: key,
      accounts: entry?.accounts ?? cached ?? [],
      fetchedAt: entry?.fetchedAt ?? 0,
      invalidated: false,
      loading: false,
    })
    notify()
    throw error
  }

  writeTradingAccountsSettingsCache(key, accounts)
  return accounts
}
