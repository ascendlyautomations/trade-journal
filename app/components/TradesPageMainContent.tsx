"use client"

import Link from "next/link"
import { memo, type Dispatch, type SetStateAction } from "react"
import EmptyState from "./ui/EmptyState"
import TradeFilterBar from "./TradeFilterBar"
import TradesPageTradeCard from "./TradesPageTradeCard"
import { SkeletonTradesPageContent } from "./ui/skeletons"
import { formatMoneyUnknown, formatRR } from "@/lib/formatDisplay"

type TradeStats = {
  totalTrades: number
  winRate: number
  totalPnL: number
  avgRR: number
}

type TradesPageMainContentProps = {
  loading: boolean
  accounts: Array<{ value: string; label: string; accountType?: string | null }>
  accountFilter: string
  onAccountChange: (value: string) => void
  accountTypeFilter: string
  onAccountTypeChange: (value: string) => void
  timeframe: string
  onTimeframeChange: (value: string) => void
  customRangeStart: string
  customRangeEnd: string
  onCustomRangeApply: (start: string, end: string) => void
  selectedDate: string
  onSelectedDateChange: (value: string) => void
  resultFilter: "all" | "wins" | "losses"
  onResultFilterChange: Dispatch<SetStateAction<"all" | "wins" | "losses">>
  showAdvanced: boolean
  onToggleAdvanced: () => void
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  tradeStats: TradeStats
  displayedTrades: any[]
  visibleTradesLength: number
  visibleCount: number
  accountById: Record<string, any>
  gateProfile: any | null
  onEditTrade: (trade: any) => void
  onDeleteTrade: (tradeId: string) => void
  onSendTrade: (trade: any) => void
  onImageClick: (imageUrl: string) => void
  onLoadMore: () => void
  onImportCsv: () => void
}

function Stat({ title, value, positive }: any) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="bg-white/5 border border-white/10 p-4 p-3 md:p-5 rounded-xl text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}

function TradesPageMainContent({
  loading,
  accounts,
  accountFilter,
  onAccountChange,
  accountTypeFilter,
  onAccountTypeChange,
  timeframe,
  onTimeframeChange,
  customRangeStart,
  customRangeEnd,
  onCustomRangeApply,
  selectedDate,
  onSelectedDateChange,
  resultFilter,
  onResultFilterChange,
  showAdvanced,
  onToggleAdvanced,
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  tradeStats,
  displayedTrades,
  visibleTradesLength,
  visibleCount,
  accountById,
  gateProfile,
  onEditTrade,
  onDeleteTrade,
  onSendTrade,
  onImageClick,
  onLoadMore,
  onImportCsv,
}: TradesPageMainContentProps) {
  if (loading) {
    return <SkeletonTradesPageContent tradeCount={6} />
  }

  return (
    <>
      <div className="w-full mt-2.5 mb-1.5">
        <TradeFilterBar
          variant="trades"
          fullWidth
          accounts={accounts}
          accountFilter={accountFilter}
          onAccountChange={onAccountChange}
          accountTypeFilter={accountTypeFilter}
          onAccountTypeChange={onAccountTypeChange}
          timeframe={timeframe}
          onTimeframeChange={onTimeframeChange}
          customRangeStart={customRangeStart}
          customRangeEnd={customRangeEnd}
          onCustomRangeApply={onCustomRangeApply}
          selectedDate={selectedDate}
          onSelectedDateChange={onSelectedDateChange}
          leading={
            <div className="flex w-full shrink-0 flex-wrap items-center justify-center gap-2 md:w-auto md:flex-nowrap">
              <button
                type="button"
                onClick={() => onResultFilterChange("all")}
                className={`whitespace-nowrap rounded-md px-3 py-1 text-sm text-white ${
                  resultFilter === "all"
                    ? "bg-emerald-500 hover:bg-emerald-600"
                    : "bg-white/10 hover:bg-white/20"
                }`}
              >
                All
              </button>

              <div className="flex items-center gap-2">
                <span
                  className={`text-sm font-semibold ${
                    resultFilter === "wins" ? "text-green-400" : "text-gray-400"
                  }`}
                >
                  W
                </span>

                <div
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault()
                      if (resultFilter === "all") {
                        onResultFilterChange("wins")
                      } else {
                        onResultFilterChange(
                          resultFilter === "wins" ? "losses" : "wins"
                        )
                      }
                    }
                  }}
                  onClick={() => {
                    if (resultFilter === "all") {
                      onResultFilterChange("wins")
                    } else {
                      onResultFilterChange(
                        resultFilter === "wins" ? "losses" : "wins"
                      )
                    }
                  }}
                  className={`relative flex h-8 w-28 cursor-pointer items-center rounded-full px-2 transition
                    ${resultFilter === "wins" ? "bg-emerald-500" : ""}
                    ${resultFilter === "losses" ? "bg-red-500" : ""}
                    ${resultFilter === "all" ? "bg-white/10" : ""}
                  `}
                >
                  <div
                    className={`h-6 w-6 transform rounded-full bg-white shadow-md transition ${
                      resultFilter === "wins"
                        ? "translate-x-0"
                        : resultFilter === "losses"
                          ? "translate-x-[4.5rem]"
                          : "translate-x-9"
                    }`}
                  />
                </div>

                <span
                  className={`text-sm font-semibold ${
                    resultFilter === "losses" ? "text-red-400" : "text-gray-400"
                  }`}
                >
                  L
                </span>
              </div>
            </div>
          }
          trailing={
            <div className="flex items-center gap-2 w-full md:w-auto">
              <button
                type="button"
                onClick={onToggleAdvanced}
                className="order-1 flex-1 h-10 px-3 rounded bg-white/10 hover:bg-white/20 text-sm text-white flex items-center justify-center md:order-3 md:h-auto md:flex-none md:rounded-md md:px-3 md:py-1.5"
              >
                {showAdvanced ? "Hide Advanced" : "Show Advanced"}
              </button>
              <button
                type="button"
                onClick={onTogglePublicOnly}
                className={`order-2 flex-[0.8] h-10 px-2 rounded text-sm font-medium transition flex items-center justify-center md:order-1 md:h-auto md:flex-none md:rounded-xl md:px-4 md:py-2
                  ${
                    showPublicOnly
                      ? "bg-blue-500 text-white"
                      : "bg-white/10 text-gray-300 hover:bg-white/20"
                  }`}
              >
                Public
              </button>
              <button
                type="button"
                onClick={onOpenPerformanceShare}
                className="order-3 h-10 w-10 rounded bg-white/10 hover:bg-white/20 flex items-center justify-center md:order-2 md:h-[34px] md:w-auto md:rounded-md md:px-3 md:py-1 md:text-sm md:text-white"
                title="Share performance"
                aria-label="Share performance"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  className="h-4 w-4 text-blue-300"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 12v7a1 1 0 001 1h14a1 1 0 001-1v-7M16 6l-4-4m0 0L8 6m4-4v12"
                  />
                </svg>
              </button>
            </div>
          }
        />
      </div>

      <div className="w-full grid grid-cols-2 md:grid-cols-4 gap-2 mb-3 mt-0">
        <Stat
          title="Trades"
          value={tradeStats.totalTrades.toLocaleString(undefined, {
            maximumFractionDigits: 0,
          })}
        />
        <Stat title="Win %" value={`${tradeStats.winRate.toFixed(1)}%`} />
        <Stat
          title="P&L"
          value={formatMoneyUnknown(tradeStats.totalPnL)}
          positive={tradeStats.totalPnL >= 0}
        />
        <Stat title="Avg RR" value={formatRR(tradeStats.avgRR)} />
      </div>

      <div className="w-full grid grid-cols-1 md:grid-cols-2 gap-4">
        {displayedTrades.length === 0 ? (
          <div className="md:col-span-2">
            <EmptyState
              title="No Trades Yet"
              description="Start tracking your performance by logging your first trade."
              action={
                <div className="flex flex-wrap items-center justify-center gap-3">
                  <Link
                    href="/app"
                    className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
                  >
                    Add Trade
                  </Link>
                  <button
                    type="button"
                    onClick={onImportCsv}
                    className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/15"
                  >
                    Import CSV
                  </button>
                </div>
              }
              className="py-10"
            />
          </div>
        ) : (
          displayedTrades.map((trade) => (
            <TradesPageTradeCard
              key={trade.id}
              trade={trade}
              showAdvanced={showAdvanced}
              accountRow={accountById[String(trade.account_id ?? "")]}
              shareProfile={gateProfile}
              onEdit={onEditTrade}
              onDelete={onDeleteTrade}
              onSendClick={onSendTrade}
              onImageClick={onImageClick}
            />
          ))
        )}
      </div>

      {visibleCount < visibleTradesLength ? (
        <div className="flex justify-center mt-4">
          <button
            type="button"
            onClick={onLoadMore}
            className="px-4 py-2 rounded-lg bg-blue-500 hover:bg-blue-600 transition"
          >
            Load More
          </button>
        </div>
      ) : null}
    </>
  )
}

export default memo(TradesPageMainContent)
