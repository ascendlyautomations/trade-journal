"use client"

import dynamic from "next/dynamic"
import { forwardRef, Suspense } from "react"
import type { TradingReportsSectionHandle } from "@/app/components/trading-reports/TradingReportsSection"
import type { DashboardTradeRow } from "./dashboardTypes"

const TradingReportsSection = dynamic(
  () => import("@/app/components/trading-reports/TradingReportsSection"),
  {
    ssr: false,
    loading: () => <div className="h-20 animate-pulse rounded-xl bg-white/5" />,
  }
)

type DashboardTradingReportsProps = {
  userId: string
  trades: DashboardTradeRow[]
  onViewTrade: (trade: DashboardTradeRow) => void
}

const DashboardTradingReports = forwardRef<
  TradingReportsSectionHandle,
  DashboardTradingReportsProps
>(function DashboardTradingReports({ userId, trades, onViewTrade }, ref) {
  return (
    <Suspense fallback={null}>
      <TradingReportsSection
        ref={ref}
        userId={userId}
        trades={trades}
        onViewTrade={onViewTrade}
      />
    </Suspense>
  )
})

export default DashboardTradingReports
