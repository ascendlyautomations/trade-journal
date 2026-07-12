"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import FreePlanAccountSlotModal, {
  type FreePlanSlotAccountOption,
} from "@/app/components/FreePlanAccountSlotModal"
import { supabase } from "@/lib/supabaseClient"
import { ACCOUNTS_SELECT, invalidateAccountsCache } from "@/lib/appDataCache"
import {
  needsFreePlanAccountSlotSelection,
} from "@/lib/freePlanAccountSlots"
import { isProActive } from "@/lib/subscription"
import { useUserProfile } from "@/lib/useUserProfile"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

type TradeStatRow = {
  account_id: string | null
  pnl: number | string | null
  exit_date: string | null
  entry_date: string | null
  created_at: string | null
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
 * with more than 3 trade-entry-enabled accounts.
 */
export default function FreePlanAccountSlotShell({
  children,
}: {
  children: React.ReactNode
}) {
  const { user, profile, loading } = useUserProfile()
  const [accounts, setAccounts] = useState<FreePlanSlotAccountOption[]>([])
  const [rawCanAddFlags, setRawCanAddFlags] = useState<
    { id: string; can_add_trades?: boolean | null }[]
  >([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const load = useCallback(async () => {
    if (!user?.id) {
      setAccounts([])
      setRawCanAddFlags([])
      return
    }
    if (isProActive(profile)) {
      setAccounts([])
      setRawCanAddFlags([])
      return
    }

    const [{ data: accountRows, error: accountsErr }, { data: tradeRows }] =
      await Promise.all([
        supabase
          .from("accounts")
          .select(ACCOUNTS_SELECT)
          .eq("user_id", user.id),
        supabase
          .from("trades")
          .select("account_id, pnl, exit_date, entry_date, created_at")
          .eq("user_id", user.id),
      ])

    if (accountsErr) {
      console.error("[FreePlanAccountSlotShell] accounts", accountsErr)
      setAccounts([])
      setRawCanAddFlags([])
      return
    }

    const rows = (accountRows ?? []) as Record<string, unknown>[]
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
    setAccounts(buildSlotAccounts(rows, (tradeRows ?? []) as TradeStatRow[]))
  }, [user?.id, profile])

  useEffect(() => {
    if (loading) return
    void load()
  }, [loading, load, refreshKey])

  const needsSelection = useMemo(
    () => needsFreePlanAccountSlotSelection(profile, rawCanAddFlags),
    [profile, rawCanAddFlags]
  )

  async function handleConfirm(accountIds: string[]) {
    if (!user?.id || saving) return
    setSaving(true)
    setError(null)
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const accessToken = session?.access_token
      if (!accessToken) {
        setError("Unauthorized")
        return
      }

      const res = await fetch("/api/accounts/select-free-slots", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ accountIds }),
      })
      const body = (await res.json().catch(() => ({}))) as {
        error?: string
      }
      if (!res.ok) {
        setError(
          body.error ||
            toUserFacingErrorMessage(
              null,
              "Could not save account selection."
            )
        )
        return
      }
      invalidateAccountsCache(user.id)
      setRefreshKey((k) => k + 1)
    } catch (err) {
      setError(
        toUserFacingErrorMessage(err, "Could not save account selection.")
      )
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      {children}
      <FreePlanAccountSlotModal
        open={!loading && Boolean(user) && needsSelection && accounts.length > 0}
        accounts={accounts}
        saving={saving}
        error={error}
        onConfirm={handleConfirm}
      />
    </>
  )
}
