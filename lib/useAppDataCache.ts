"use client"

import { useCallback, useEffect, useSyncExternalStore } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  EMPTY_ACCOUNTS,
  EMPTY_TRADES,
  ensureAccountsLoaded,
  ensureTradesLoaded,
  getAccountsLoadingSnapshot,
  getAccountsSnapshot,
  getTradesLoadingSnapshot,
  getTradesSnapshot,
  subscribeAppDataCache,
} from "@/lib/appDataCache"

function getTradesServerSnapshot(): readonly any[] {
  return EMPTY_TRADES
}

function getAccountsServerSnapshot(): readonly any[] {
  return EMPTY_ACCOUNTS
}

function getTradesLoadingServerSnapshot(): boolean {
  return false
}

function getAccountsLoadingServerSnapshot(): boolean {
  return false
}

export function useCachedTrades(
  userId: string | null | undefined,
  options?: { fullHistory?: boolean }
) {
  const fullHistory = options?.fullHistory === true

  const trades = useSyncExternalStore(
    subscribeAppDataCache,
    () => getTradesSnapshot(userId),
    getTradesServerSnapshot
  )

  const loading = useSyncExternalStore(
    subscribeAppDataCache,
    () => getTradesLoadingSnapshot(userId),
    getTradesLoadingServerSnapshot
  )

  useEffect(() => {
    if (!userId) return
    void ensureTradesLoaded(supabase, userId, { fullHistory })
  }, [userId, fullHistory])

  const refresh = useCallback(async () => {
    if (!userId) return []
    return ensureTradesLoaded(supabase, userId, {
      force: true,
      fullHistory,
    })
  }, [userId, fullHistory])

  return { trades, loading, refresh }
}

export function useCachedAccounts(userId: string | null | undefined) {
  const accounts = useSyncExternalStore(
    subscribeAppDataCache,
    () => getAccountsSnapshot(userId),
    getAccountsServerSnapshot
  )

  const loading = useSyncExternalStore(
    subscribeAppDataCache,
    () => getAccountsLoadingSnapshot(userId),
    getAccountsLoadingServerSnapshot
  )

  useEffect(() => {
    if (!userId) return
    void ensureAccountsLoaded(supabase, userId)
  }, [userId])

  const refresh = useCallback(async () => {
    if (!userId) return []
    return ensureAccountsLoaded(supabase, userId, { force: true })
  }, [userId])

  return { accounts, loading, refresh }
}
