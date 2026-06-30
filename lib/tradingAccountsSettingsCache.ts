import type { SupabaseClient } from "@supabase/supabase-js"
import {
  ensureAccountsLoaded,
  getCachedAccounts,
  invalidateAccountsCache,
} from "@/lib/appDataCache"
import { mapTradingAccountRow, type TradingAccountListItem } from "@/lib/tradingAccounts"

/** Legacy session key — cleared on sign-out so old caches cannot mask appDataCache. */
const STORAGE_KEY = "tj_trading_accounts_settings_v1"

export function subscribeTradingAccountsSettingsCache(listener: () => void) {
  return () => {
    void listener
  }
}

export function getCachedTradingAccountsSettings(
  userId: string | null | undefined
): TradingAccountListItem[] | null {
  const cached = getCachedAccounts(userId)
  if (!cached) return null
  return cached.map((row) =>
    mapTradingAccountRow(row as Record<string, unknown>)
  )
}

export function writeTradingAccountsSettingsCache(
  _userId: string,
  _accounts: TradingAccountListItem[]
) {
  // No-op: settings accounts live in appDataCache.
}

export function invalidateTradingAccountsSettingsCache(userId: string) {
  invalidateAccountsCache(userId)
}

export function clearAllTradingAccountsSettingsCaches() {
  if (typeof window !== "undefined") {
    try {
      sessionStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
}

export async function ensureTradingAccountsSettingsLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<TradingAccountListItem[]> {
  const rows = await ensureAccountsLoaded(client, userId, options)
  return rows.map((row) =>
    mapTradingAccountRow(row as Record<string, unknown>)
  )
}
