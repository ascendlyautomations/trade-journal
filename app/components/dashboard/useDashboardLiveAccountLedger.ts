"use client"

import { useEffect, useMemo, useState, useSyncExternalStore } from "react"
import {
  fetchManualPayoutEntriesForAccount,
  type ManualPayoutLedgerEntry,
} from "@/lib/accountPayoutEntry"
import {
  isTradesHistoryComplete,
  subscribeAppDataCache,
} from "@/lib/appDataCache"
import {
  resolveDashboardLiveSingleAccountId,
  type DashboardLiveAccountSource,
} from "@/lib/dashboardLiveAccountValue"
import { supabase } from "@/lib/supabaseClient"
import { useCachedTrades } from "@/lib/useAppDataCache"
import {
  getWithdrawalsLedgerGeneration,
  subscribeWithdrawalsLedger,
} from "@/lib/withdrawalsLedgerInvalidate"

export type DashboardLiveAccountLedgerState =
  | { active: false }
  | {
      active: true
      accountId: string
      account: DashboardLiveAccountSource
      trades: ReturnType<typeof useCachedTrades>["trades"]
      ledgerEntries: ManualPayoutLedgerEntry[]
      status: "loading"
    }
  | {
      active: true
      accountId: string
      account: DashboardLiveAccountSource
      trades: ReturnType<typeof useCachedTrades>["trades"]
      ledgerEntries: ManualPayoutLedgerEntry[]
      status: "ready"
    }

type UseDashboardLiveAccountLedgerOptions = {
  userId: string | null | undefined
  accountFilter: string
  accountById: Record<string, DashboardLiveAccountSource | null | undefined>
  propFirmAccountId: string | null | undefined
}

export function useDashboardLiveAccountLedger({
  userId,
  accountFilter,
  accountById,
  propFirmAccountId,
}: UseDashboardLiveAccountLedgerOptions): DashboardLiveAccountLedgerState {
  const accountId = useMemo(
    () =>
      resolveDashboardLiveSingleAccountId({
        userId,
        accountFilter,
        accountById,
        propFirmAccountId,
      }),
    [userId, accountFilter, accountById, propFirmAccountId]
  )

  const loadFullHistory = accountId != null
  const { trades, loading: tradesLoading } = useCachedTrades(userId, {
    fullHistory: loadFullHistory,
  })

  const tradesHistoryComplete = useSyncExternalStore(
    subscribeAppDataCache,
    () =>
      userId && loadFullHistory ? isTradesHistoryComplete(userId) : true,
    () => false
  )

  const [ledgerEntries, setLedgerEntries] = useState<ManualPayoutLedgerEntry[]>(
    []
  )
  const [ledgerLoading, setLedgerLoading] = useState(false)

  const ledgerGeneration = useSyncExternalStore(
    subscribeWithdrawalsLedger,
    getWithdrawalsLedgerGeneration,
    getWithdrawalsLedgerGeneration
  )

  useEffect(() => {
    if (!accountId) {
      setLedgerEntries([])
      setLedgerLoading(false)
      return
    }
    let cancelled = false
    setLedgerEntries([])
    setLedgerLoading(true)
    void fetchManualPayoutEntriesForAccount(supabase, accountId).then((rows) => {
      if (!cancelled) {
        setLedgerEntries(rows)
        setLedgerLoading(false)
      }
    })
    return () => {
      cancelled = true
    }
  }, [accountId, ledgerGeneration])

  return useMemo((): DashboardLiveAccountLedgerState => {
    if (!accountId) return { active: false }
    const account = accountById[accountId]
    if (!account) return { active: false }

    const base = {
      active: true as const,
      accountId,
      account,
      trades,
      ledgerEntries,
    }

    if (tradesLoading || !tradesHistoryComplete || ledgerLoading) {
      return { ...base, status: "loading" }
    }

    return { ...base, status: "ready" }
  }, [
    accountById,
    accountId,
    ledgerEntries,
    ledgerLoading,
    trades,
    tradesHistoryComplete,
    tradesLoading,
  ])
}
