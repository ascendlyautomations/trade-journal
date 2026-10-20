"use client"

import { useMemo } from "react"
import type { ManualPayoutLedgerEntry } from "@/lib/accountPayoutEntry"
import { computeLiveLedgerAccountValue } from "@/lib/dashboardLiveAccountValue"
import { useDashboardLiveAccountLedger } from "@/app/components/dashboard/useDashboardLiveAccountLedger"

export type DashboardLiveAccountValueState =
  | { visible: false }
  | { visible: true; status: "loading" }
  | {
      visible: true
      status: "ready"
      balance: number
      /** Manual ledger rows for the selected Live account (same source as balance). */
      ledgerEntries: ManualPayoutLedgerEntry[]
    }

type UseDashboardLiveAccountValueOptions = {
  userId: string | null | undefined
  accountFilter: string
  accountById: Record<
    string,
    { account_size?: unknown; category?: unknown; mode?: unknown } | null | undefined
  >
  /** When set, Prop Firm snapshot owns balance for this account. */
  propFirmAccountId: string | null | undefined
}

export function useDashboardLiveAccountValue(
  options: UseDashboardLiveAccountValueOptions
): DashboardLiveAccountValueState {
  const ledger = useDashboardLiveAccountLedger(options)

  return useMemo((): DashboardLiveAccountValueState => {
    if (!ledger.active) return { visible: false }
    if (ledger.status === "loading") {
      return { visible: true, status: "loading" }
    }

    const balance = computeLiveLedgerAccountValue(
      ledger.account,
      ledger.trades,
      ledger.accountId,
      ledger.ledgerEntries
    )

    return {
      visible: true,
      status: "ready",
      balance,
      ledgerEntries: ledger.ledgerEntries,
    }
  }, [ledger])
}
