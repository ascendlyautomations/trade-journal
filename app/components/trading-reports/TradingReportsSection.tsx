"use client"

import { forwardRef, Suspense, useCallback, useEffect, useImperativeHandle, useMemo, useState } from "react"
import { useSearchParams } from "next/navigation"
import TradingReportModal from "@/app/components/trading-reports/TradingReportModal"
import TradingReportsDashboardCard from "@/app/components/trading-reports/TradingReportsDashboardCard"
import { useTradingReports } from "@/lib/useTradingReports"
import type { TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"

const VALID_PERIOD_KEYS = new Set<TradingReportPeriodKey>([
  "weekly_this",
  "weekly_last",
  "monthly_this",
  "monthly_last",
])

function parsePeriodKey(value: string | null): TradingReportPeriodKey | null {
  if (!value) return null
  return VALID_PERIOD_KEYS.has(value as TradingReportPeriodKey)
    ? (value as TradingReportPeriodKey)
    : null
}

type TradingReportsSectionProps = {
  userId: string | null | undefined
  trades: any[]
  onViewTrade: (trade: { id?: string | null }) => void
}

export type TradingReportsSectionHandle = {
  openReport: () => void
}

const TradingReportsSection = forwardRef<
  TradingReportsSectionHandle,
  TradingReportsSectionProps
>(function TradingReportsSection(
  { userId, trades, onViewTrade },
  ref
) {
  const searchParams = useSearchParams()
  const { snapshot, loading, newBadge, getReport, markSeen } = useTradingReports(
    userId,
    trades
  )

  const [open, setOpen] = useState(false)
  const [periodKey, setPeriodKey] = useState<TradingReportPeriodKey>("weekly_this")

  const report = useMemo(
    () => getReport(periodKey) ?? snapshot?.reports[periodKey] ?? null,
    [getReport, periodKey, snapshot]
  )

  const bestTrade = useMemo(() => {
    if (!report?.bestTradeId) return null
    return trades.find((trade) => String(trade.id) === report.bestTradeId) ?? null
  }, [report?.bestTradeId, trades])

  const openModal = useCallback(
    (key?: TradingReportPeriodKey) => {
      const nextKey = key ?? periodKey
      setPeriodKey(nextKey)
      setOpen(true)
      if (userId) {
        if (nextKey === "weekly_last" || nextKey === "monthly_last") {
          markSeen(nextKey)
        }
      }
    },
    [markSeen, periodKey, userId]
  )

  const openDefaultReport = useCallback(() => {
    openModal(
      newBadge?.kind === "monthly"
        ? "monthly_last"
        : newBadge?.kind === "weekly"
          ? "weekly_last"
          : "weekly_this"
    )
  }, [newBadge, openModal])

  useImperativeHandle(ref, () => ({ openReport: openDefaultReport }), [
    openDefaultReport,
  ])

  useEffect(() => {
    const fromUrl = parsePeriodKey(searchParams.get("report"))
    if (fromUrl) {
      openModal(fromUrl)
    }
  }, [searchParams, openModal])

  useEffect(() => {
    if (!open || !userId) return
    if (periodKey === "weekly_last" || periodKey === "monthly_last") {
      markSeen(periodKey)
    }
  }, [open, periodKey, markSeen, userId])

  if (!userId) return null

  return (
    <>
      <div className="hidden md:block">
        <TradingReportsDashboardCard
          onOpen={openDefaultReport}
          loading={loading && !snapshot}
          newBadge={newBadge}
        />
      </div>

      <TradingReportModal
        open={open}
        onClose={() => setOpen(false)}
        report={report}
        periodKey={periodKey}
        onPeriodChange={setPeriodKey}
        bestTrade={bestTrade}
        viewerUserId={userId}
        onViewTrade={onViewTrade}
      />
    </>
  )
})

export default TradingReportsSection
