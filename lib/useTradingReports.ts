"use client"

import { useCallback, useEffect, useSyncExternalStore } from "react"
import { subscribeAppDataCache } from "@/lib/appDataCache"
import {
  ensureTradingReportsLoaded,
  getNewTradingReportBadge,
  getTradingReportFromSnapshot,
  getTradingReportsSnapshot,
  isTradingReportsLoading,
  subscribeTradingReportsCache,
} from "@/lib/tradingReports/tradingReportCache"
import { markTradingReportSeen, subscribeTradingReportSeen } from "@/lib/tradingReports/tradingReportSeen"
import type { TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"

export function useTradingReports(
  userId: string | null | undefined,
  trades: any[]
) {
  const subscribe = useCallback(
    (listener: () => void) => {
      const unsubReports = subscribeTradingReportsCache(listener)
      const unsubTrades = subscribeAppDataCache(listener)
      const unsubSeen = subscribeTradingReportSeen(listener)
      return () => {
        unsubReports()
        unsubTrades()
        unsubSeen()
      }
    },
    []
  )

  const snapshot = useSyncExternalStore(
    subscribe,
    () => getTradingReportsSnapshot(userId),
    () => null
  )

  const loading = useSyncExternalStore(
    subscribe,
    () => isTradingReportsLoading(userId),
    () => false
  )

  const newBadge = useSyncExternalStore(
    subscribe,
    () => getNewTradingReportBadge(userId),
    () => null
  )

  useEffect(() => {
    if (!userId) return
    ensureTradingReportsLoaded(trades, userId)
  }, [userId, trades])

  const getReport = useCallback(
    (periodKey: TradingReportPeriodKey) =>
      getTradingReportFromSnapshot(userId, periodKey),
    [userId, snapshot]
  )

  const markSeen = useCallback(
    (periodKey: TradingReportPeriodKey) => {
      if (!userId) return
      markTradingReportSeen(userId, periodKey)
    },
    [userId]
  )

  return {
    snapshot,
    loading,
    newBadge,
    getReport,
    markSeen,
  }
}
