"use client"

import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react"
import {
  fetchAccountPayoutEntriesForUser,
  groupPayoutEntriesByAccountId,
} from "@/lib/accountPayoutEntry"
import {
  buildPayoutHistoryItems,
  type PayoutHistoryItem,
} from "@/lib/payoutHistory"
import { fetchPayoutCycleHistoryForUser } from "@/lib/propfirmPayoutCycles"
import { resolveWithdrawalsAccountRows } from "@/lib/withdrawalsAccountRows"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureAccountsLoaded,
  subscribeAppDataCache,
} from "@/lib/appDataCache"
import {
  getWithdrawalsLedgerGeneration,
  subscribeWithdrawalsLedger,
} from "@/lib/withdrawalsLedgerInvalidate"

export type WithdrawalsHistoryState = {
  loading: boolean
  error: string | null
  loadWarnings: string[]
  items: PayoutHistoryItem[]
  accounts: Array<{
    id: string
    name?: string | null
    mode?: unknown
    category?: unknown
  }>
  accountsById: Record<
    string,
    { id: string; name?: string | null; mode?: unknown; category?: unknown }
  >
  refresh: () => Promise<void>
}

export function useWithdrawalsHistory(
  userId: string | null | undefined
): WithdrawalsHistoryState {
  const [loading, setLoading] = useState(Boolean(userId))
  const [error, setError] = useState<string | null>(null)
  const [loadWarnings, setLoadWarnings] = useState<string[]>([])
  const [items, setItems] = useState<PayoutHistoryItem[]>([])
  const [accounts, setAccounts] = useState<
    WithdrawalsHistoryState["accounts"]
  >([])

  const ledgerGeneration = useSyncExternalStore(
    subscribeWithdrawalsLedger,
    getWithdrawalsLedgerGeneration,
    getWithdrawalsLedgerGeneration
  )

  const refresh = useCallback(async () => {
    if (!userId) {
      setItems([])
      setAccounts([])
      setLoadWarnings([])
      setLoading(false)
      return
    }

    setLoading(true)
    setError(null)
    setLoadWarnings([])
    try {
      const loadedAccounts = await ensureAccountsLoaded(supabase, userId, {
        force: true,
      })

      const [entriesResult, cyclesResult] = await Promise.all([
        fetchAccountPayoutEntriesForUser(supabase, userId),
        fetchPayoutCycleHistoryForUser(supabase, userId),
      ])

      const warnings: string[] = []
      if (entriesResult.error) {
        warnings.push(`Live withdrawals: ${entriesResult.error}`)
      }
      if (cyclesResult.error) {
        warnings.push(`Prop payouts: ${cyclesResult.error}`)
      }
      if (entriesResult.error && cyclesResult.error) {
        setError(
          "Could not load withdrawal history. Check your connection and try again."
        )
        setItems([])
        setAccounts([])
        setLoadWarnings(warnings)
        return
      }
      setLoadWarnings(warnings)

      const accountRows = await resolveWithdrawalsAccountRows(
        supabase,
        userId,
        loadedAccounts as Record<string, unknown>[],
        entriesResult.entries,
        cyclesResult.cyclesByAccount
      )
      setAccounts(accountRows)

      const entriesByAccount = groupPayoutEntriesByAccountId(
        entriesResult.entries
      )
      const history = buildPayoutHistoryItems({
        accounts: accountRows,
        entriesByAccount,
        cyclesByAccount: cyclesResult.cyclesByAccount,
      })
      setItems(history)
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Could not load withdrawals."
      )
      setItems([])
      setAccounts([])
      setLoadWarnings([])
    } finally {
      setLoading(false)
    }
  }, [userId])

  useEffect(() => {
    void refresh()
  }, [refresh, ledgerGeneration])

  const accountsById = useMemo(() => {
    const map: WithdrawalsHistoryState["accountsById"] = {}
    for (const account of accounts) {
      map[account.id] = account
    }
    return map
  }, [accounts])

  return {
    loading,
    error,
    loadWarnings,
    items,
    accounts,
    accountsById,
    refresh,
  }
}
