"use client"

import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react"
import {
  fetchAccountPayoutEntriesForUser,
  groupPayoutEntriesByAccountId,
} from "@/lib/accountPayoutEntry"
import { isPayoutAchievementType } from "@/lib/achievementTypes"
import {
  buildPayoutHistoryItems,
  payoutAchievementsMissingFromHistory,
  type PayoutHistoryItem,
  type UnmatchedPayoutAchievement,
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
      const recorded = buildPayoutHistoryItems({
        accounts: accountRows,
        entriesByAccount,
        cyclesByAccount: cyclesResult.cyclesByAccount,
      })
      const achievements = await fetchUnmatchedPayoutAchievements(userId)
      if (achievements.warning) warnings.push(achievements.warning)
      setLoadWarnings(warnings)
      const history = [
        ...recorded,
        ...payoutAchievementsMissingFromHistory(achievements.rows, recorded),
      ].sort((a, b) => b.dateMs - a.dateMs)
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

function metadataId(metadata: unknown, key: string): string | null {
  if (!metadata || typeof metadata !== "object") return null
  const value = (metadata as Record<string, unknown>)[key]
  const id = String(value ?? "").trim()
  return id || null
}

async function fetchUnmatchedPayoutAchievements(
  userId: string
): Promise<{ rows: UnmatchedPayoutAchievement[]; warning: string | null }> {
  const { data, error } = await supabase
    .from("achievements")
    .select(
      "id, achievement_type, title, value_numeric, achieved_at, created_at, account_id, account_name, metadata"
    )
    .eq("user_id", userId)

  if (error) {
    return { rows: [], warning: `Profile payouts: ${error.message}` }
  }

  const rows = (data ?? [])
    .filter((row) => isPayoutAchievementType(row.achievement_type))
    .map((row) => ({
      id: row.id,
      achievementType: row.achievement_type,
      title: row.account_name?.trim() || row.title,
      amount: Number(row.value_numeric) || 0,
      achievedAt: row.achieved_at,
      createdAt: row.created_at,
      accountId: row.account_id,
      linkedCycleId: metadataId(row.metadata, "account_payout_cycle_id"),
      linkedEntryId: metadataId(row.metadata, "account_payout_entry_id"),
    }))

  return { rows, warning: null }
}
