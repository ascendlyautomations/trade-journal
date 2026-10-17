"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import FreePlanAccountSlotModal, {
  type FreePlanSlotAccountOption,
} from "@/app/components/FreePlanAccountSlotModal"
import { supabase } from "@/lib/supabaseClient"
import {
  ACCOUNTS_SELECT,
  ensureTradesLoaded,
  setAccountsCache,
} from "@/lib/appDataCache"
import {
  freePlanSlotSelectionRequired,
  persistedTradeEntrySelectionIds,
} from "@/lib/freePlanAccountSlots"
import { fetchServerTraxProActive } from "@/lib/fetchServerTraxProActive"
import { isProActive } from "@/lib/subscription"
import { useUserProfile } from "@/lib/useUserProfile"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { invalidateSessionBootstrap } from "@/lib/backendV2/sessionBootstrapCache.ts"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"

type TradeStatRow = {
  account_id: string | null
  pnl: number | string | null
  exit_date: string | null
  entry_date: string | null
  created_at: string | null
}

type FreePlanAccountSlotContextValue = {
  openSelection: () => void
  canReconfigureActiveAccounts: boolean
  viewerIsConfirmedFree: boolean
}

const FreePlanAccountSlotContext =
  createContext<FreePlanAccountSlotContextValue | null>(null)

export function useFreePlanAccountSlotSelection() {
  return useContext(FreePlanAccountSlotContext)
}

function tradeDateMs(row: TradeStatRow): number {
  for (const raw of [row.exit_date, row.entry_date, row.created_at]) {
    if (!raw) continue
    const ms = Date.parse(String(raw))
    if (!Number.isNaN(ms)) return ms
  }
  return 0
}

function buildSlotAccounts(
  accountRows: readonly Record<string, unknown>[],
  tradeRows: readonly TradeStatRow[]
): FreePlanSlotAccountOption[] {
  const stats = new Map<
    string,
    { tradeCount: number; lifetimePnl: number; lastTradeMs: number }
  >()

  for (const trade of tradeRows) {
    const id = String(trade.account_id ?? "").trim()
    if (!id) continue
    const prev = stats.get(id) ?? {
      tradeCount: 0,
      lifetimePnl: 0,
      lastTradeMs: 0,
    }
    const pnl = Number(trade.pnl)
    prev.tradeCount += 1
    if (Number.isFinite(pnl)) prev.lifetimePnl += pnl
    prev.lastTradeMs = Math.max(prev.lastTradeMs, tradeDateMs(trade))
    stats.set(id, prev)
  }

  return accountRows.map((row) => {
    const id = String(row.id ?? "")
    const stat = stats.get(id)
    return {
      id,
      name: String(row.name ?? ""),
      size: row.account_size != null ? String(row.account_size) : "",
      mode: row.mode != null ? String(row.mode) : null,
      category: row.category != null ? String(row.category) : null,
      tradeCount: stat?.tradeCount ?? 0,
      lifetimePnl: stat?.lifetimePnl ?? 0,
      lastTradeDate:
        stat && stat.lastTradeMs > 0
          ? new Date(stat.lastTradeMs).toISOString()
          : null,
    }
  })
}

/**
 * Shows the Free-plan account selection modal when a user loses Pro/trial
 * with more than 3 trade-entry-enabled accounts, or when opened from Settings.
 */
export default function FreePlanAccountSlotShell({
  children,
}: {
  children: React.ReactNode
}) {
  const { user, profile, loading } = useUserProfile()
  const profileIsPro = isProActive(profile)
  const [accounts, setAccounts] = useState<FreePlanSlotAccountOption[]>([])
  const [rawCanAddFlags, setRawCanAddFlags] = useState<
    { id: string; can_add_trades?: boolean | null }[]
  >([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)
  const [manualOpen, setManualOpen] = useState(false)
  const [traxProActive, setTraxProActive] = useState<boolean | null>(null)
  const [entitlementReady, setEntitlementReady] = useState(false)
  const savingRef = useRef(false)

  useEffect(() => {
    if (loading || !user?.id) {
      setTraxProActive(null)
      setEntitlementReady(false)
      return
    }
    if (profileIsPro) {
      setTraxProActive(true)
      setEntitlementReady(true)
      return
    }

    let cancelled = false
    setEntitlementReady(false)
    setTraxProActive(null)
    void fetchServerTraxProActive().then((value) => {
      if (cancelled) return
      setTraxProActive(value)
      setEntitlementReady(true)
    })
    return () => {
      cancelled = true
    }
  }, [loading, user?.id, profileIsPro])

  const load = useCallback(async () => {
    if (!user?.id || !entitlementReady) {
      return
    }
    if (traxProActive !== false) {
      setAccounts([])
      setRawCanAddFlags([])
      return
    }
    if (savingRef.current) return

    let tradeRows: unknown[] = []
    try {
      tradeRows = await ensureTradesLoaded(supabase, user.id)
    } catch (loadErr) {
      console.error("[FreePlanAccountSlotShell] trades", loadErr)
    }

    const { data, error: accountsError } = await supabase
      .from("accounts")
      .select(ACCOUNTS_SELECT)
      .eq("user_id", user.id)

    if (accountsError || !data) {
      console.error("[FreePlanAccountSlotShell] accounts", accountsError)
      return
    }

    const rows = data as Record<string, unknown>[]
    setRawCanAddFlags(
      rows.map((row) => ({
        id: String(row.id ?? ""),
        can_add_trades:
          row.can_add_trades === false
            ? false
            : row.can_add_trades === true
              ? true
              : null,
      }))
    )
    setAccounts(buildSlotAccounts(rows, tradeRows as TradeStatRow[]))
    setAccountsCache(user.id, rows)
  }, [user?.id, entitlementReady, traxProActive])

  useEffect(() => {
    if (loading || !entitlementReady) return
    void load()
  }, [loading, entitlementReady, load, refreshKey])

  const viewerIsConfirmedFree = entitlementReady && traxProActive === false

  const needsSelection = useMemo(
    () => freePlanSlotSelectionRequired(traxProActive, rawCanAddFlags),
    [traxProActive, rawCanAddFlags]
  )

  const canReconfigureActiveAccounts = useMemo(() => {
    if (!viewerIsConfirmedFree) return false
    return rawCanAddFlags.length > FREE_PLAN_ACCOUNT_LIMIT
  }, [viewerIsConfirmedFree, rawCanAddFlags.length])

  const initialSelectedIds = useMemo(
    () => persistedTradeEntrySelectionIds(rawCanAddFlags),
    [rawCanAddFlags]
  )

  const modalOpen =
    viewerIsConfirmedFree &&
    Boolean(user) &&
    accounts.length > 0 &&
    (needsSelection || manualOpen)

  async function handleConfirm(accountIds: string[]) {
    if (!user?.id || savingRef.current || !viewerIsConfirmedFree) return
    const ids = [
      ...new Set(
        accountIds.map((id) => String(id).trim()).filter((id) => id.length > 0)
      ),
    ]
    if (ids.length < 1 || ids.length > FREE_PLAN_ACCOUNT_LIMIT) {
      setError(
        `Select 1 to ${FREE_PLAN_ACCOUNT_LIMIT} accounts to keep active.`
      )
      return
    }

    savingRef.current = true
    setSaving(true)
    setError(null)
    try {
      const { error: rpcError } = await supabase.rpc(
        "select_free_plan_trade_accounts",
        { p_account_ids: ids }
      )
      if (rpcError) {
        setError(
          toUserFacingErrorMessage(rpcError, "Could not save account selection.")
        )
        return
      }

      const { data, error: readError } = await supabase
        .from("accounts")
        .select(ACCOUNTS_SELECT)
        .eq("user_id", user.id)

      if (readError || !data) {
        setError(
          toUserFacingErrorMessage(
            readError,
            "Could not reload accounts to confirm the selection."
          )
        )
        return
      }

      const rows = data as Record<string, unknown>[]
      const enabled = new Set(
        rows
          .filter((row) => row.can_add_trades === true)
          .map((row) => String(row.id ?? ""))
      )
      const matches =
        enabled.size === ids.length && ids.every((id) => enabled.has(id))

      if (!matches) {
        setError(
          "Your account selection was not saved. The accounts on file do not match what you chose."
        )
        return
      }

      setRawCanAddFlags(
        rows.map((row) => ({
          id: String(row.id ?? ""),
          can_add_trades:
            row.can_add_trades === false
              ? false
              : row.can_add_trades === true
                ? true
                : null,
        }))
      )
      setAccountsCache(user.id, rows)
      invalidateSessionBootstrap(user.id)
      setManualOpen(false)
      setRefreshKey((k) => k + 1)
    } catch (err) {
      setError(
        toUserFacingErrorMessage(err, "Could not save account selection.")
      )
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  const contextValue = useMemo(
    (): FreePlanAccountSlotContextValue => ({
      openSelection: () => setManualOpen(true),
      canReconfigureActiveAccounts,
      viewerIsConfirmedFree,
    }),
    [canReconfigureActiveAccounts, viewerIsConfirmedFree]
  )

  return (
    <FreePlanAccountSlotContext.Provider value={contextValue}>
      {children}
      <FreePlanAccountSlotModal
        open={modalOpen}
        accounts={accounts}
        initialSelectedIds={initialSelectedIds}
        saving={saving}
        error={error}
        onConfirm={handleConfirm}
      />
    </FreePlanAccountSlotContext.Provider>
  )
}
