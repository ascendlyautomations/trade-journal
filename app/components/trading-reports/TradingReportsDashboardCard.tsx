"use client"

import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"
import type { NewTradingReportBadge } from "@/lib/tradingReports/tradingReportTypes"

type TradingReportsDashboardCardProps = {
  onOpen: () => void
  loading?: boolean
  newBadge: NewTradingReportBadge
}

export default function TradingReportsDashboardCard({
  onOpen,
  loading = false,
  newBadge,
}: TradingReportsDashboardCardProps) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className={`${dashboardInsightCardClass} md:p-3 group w-full text-left transition hover:border-blue-400/30 hover:bg-white/[0.12]`}
    >
      <div className="flex flex-col gap-2 md:flex-row md:items-center md:gap-3 md:justify-between">
        <div className="min-w-0 md:flex-1">
          <div className="md:hidden">
            <h2 className="text-sm font-semibold text-white">
              Trading Reports
            </h2>
            <p className="mt-0.5 text-xs leading-snug text-gray-400">
              AI-powered summaries of your recent trading performance.
            </p>
          </div>
          <h2 className="hidden min-w-0 truncate text-sm font-semibold leading-snug text-white md:block lg:text-[0.9375rem]">
            <span>Trading Reports</span>
            <span className="font-normal text-gray-400">
              , AI-powered summaries of your recent trading performance.
            </span>
          </h2>
        </div>
        <div className="shrink-0">
          {loading ? (
            <span className="inline-flex rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs text-gray-400">
              Preparing…
            </span>
          ) : newBadge ? (
            <span className="inline-flex rounded-full border border-emerald-400/30 bg-emerald-500/10 px-3 py-1 text-xs font-medium text-emerald-200">
              {newBadge.label}
            </span>
          ) : (
            <span className="inline-flex min-h-[44px] items-center rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] text-gray-400 group-hover:text-gray-300 md:min-h-0 md:px-3 md:text-xs">
              View report →
            </span>
          )}
        </div>
      </div>
    </button>
  )
}
