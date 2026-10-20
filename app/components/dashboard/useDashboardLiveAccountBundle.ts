"use client"

import { useMemo } from "react"
import {
  computeLiveAccountEquityChartData,
  computeLiveLedgerAccountValue,
  type DashboardEquityChartPoint,
} from "@/lib/dashboardLiveAccountValue"
import {
  computeLivePersonalDrawdownEquitySeries,
  parseLivePersonalDrawdownConfigFromAccount,
} from "@/lib/livePersonalDrawdown"
import { useDashboardLiveAccountLedger } from "@/app/components/dashboard/useDashboardLiveAccountLedger"
import type { DashboardLiveAccountValueState } from "@/app/components/dashboard/useDashboardLiveAccountValue"

export type DashboardLiveEquityChartPoint = DashboardEquityChartPoint & {
  drawdownFloor?: number | null
}

export type DashboardLiveEquityCurveState =
  | { mode: "pnl" }
  | { mode: "balance"; status: "loading" }
  | {
      mode: "balance"
      status: "ready"
      data: DashboardLiveEquityChartPoint[]
      hasPersonalDrawdownFloor: boolean
    }

type UseDashboardLiveAccountBundleOptions = {
  userId: string | null | undefined
  accountFilter: string
  accountById: Record<
    string,
    { account_size?: unknown; category?: unknown; mode?: unknown } | null | undefined
  >
  propFirmAccountId: string | null | undefined
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
}

export function useDashboardLiveAccountBundle(
  options: UseDashboardLiveAccountBundleOptions
): {
  liveAccountValueState: DashboardLiveAccountValueState
  liveEquityCurveState: DashboardLiveEquityCurveState
} {
  const ledger = useDashboardLiveAccountLedger(options)

  const liveAccountValueState = useMemo((): DashboardLiveAccountValueState => {
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

  const liveEquityCurveState = useMemo((): DashboardLiveEquityCurveState => {
    if (!ledger.active) return { mode: "pnl" }
    if (ledger.status === "loading") {
      return { mode: "balance", status: "loading" }
    }

    const period = {
      timeFilter: options.timeFilter,
      selectedDate: options.selectedDate,
      customRangeStart: options.customRangeStart,
      customRangeEnd: options.customRangeEnd,
    }

    const personalConfig = parseLivePersonalDrawdownConfigFromAccount(
      ledger.account
    )

    if (personalConfig) {
      const data = computeLivePersonalDrawdownEquitySeries({
        account: ledger.account,
        accountId: ledger.accountId,
        config: personalConfig,
        lifetimeTrades: ledger.trades,
        ledgerEntries: ledger.ledgerEntries,
        period,
      })
      return {
        mode: "balance",
        status: "ready",
        data,
        hasPersonalDrawdownFloor: true,
      }
    }

    const data = computeLiveAccountEquityChartData({
      account: ledger.account,
      accountId: ledger.accountId,
      lifetimeTrades: ledger.trades,
      ledgerEntries: ledger.ledgerEntries,
      period,
    })

    return {
      mode: "balance",
      status: "ready",
      data,
      hasPersonalDrawdownFloor: false,
    }
  }, [
    ledger,
    options.customRangeEnd,
    options.customRangeStart,
    options.selectedDate,
    options.timeFilter,
  ])

  return { liveAccountValueState, liveEquityCurveState }
}
