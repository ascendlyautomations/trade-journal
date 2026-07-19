"use client"

import Link from "next/link"
import { memo, type Dispatch, type SetStateAction } from "react"
import EmptyState from "./ui/EmptyState"
import Button from "./ui/Button"
import TradeFilterBar from "./TradeFilterBar"
import PerformanceShareButton from "./PerformanceShareButton"
import TradesPageTradeCard from "./TradesPageTradeCard"
import {
  SkeletonStatsCard,
  SkeletonTradesPageTradeCard,
} from "./ui/skeletons"
import { formatMoneyUnknown, formatRR } from "@/lib/formatDisplay"

type TradeStats = {
  totalTrades: number
  winRate: number
  totalPnL: number
  avgRR: number | null
}

type TradesPageMainContentProps = {
  loading: boolean
  accounts: Array<{ value: string; label: string; accountType?: string | null }>
  accountFilter: string
  onAccountChange: (value: string) => void
  isPro?: boolean
  copyGroups?: import("@/lib/copyTradingGroups").CopyTradingGroup[]
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
  /** Opens the existing Quick Trade flow. */
  onOpenQuickInput: () => void
  showAdvanced: boolean
  onToggleAdvanced: () => void
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  tradeStats: TradeStats
  displayedTrades: any[]
  visibleTradesLength: number
  hasAnyTrades: boolean
  visibleCount: number
  accountById: Record<string, any>
  gateProfile: any | null
  onEditTrade: (trade: any) => void
  onDeleteTrade: (tradeId: string) => void
  onSendTrade: (trade: any) => void
  onAnalyzeTrade?: (trade: any) => void
  onImageClick: (imageUrl: string) => void
  onLoadMore: () => void
  onImportCsv: () => void
  tradeReelsByTradeId?: Record<string, import("@/lib/reels").ReelRow>
  onOpenTradeReplay?: (trade: any) => void
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
  isPro = false,
  copyGroups = [],
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
  onOpenQuickInput,
  showAdvanced,
  onToggleAdvanced,
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  tradeStats,
  displayedTrades,
  visibleTradesLength,
  hasAnyTrades,
  visibleCount,
  accountById,
  gateProfile,
  onEditTrade,
  onDeleteTrade,
  onSendTrade,
  onAnalyzeTrade,
  onImageClick,
  onLoadMore,
  onImportCsv,
  tradeReelsByTradeId = {},
  onOpenTradeReplay,
}: TradesPageMainContentProps) {
  return (
    <>
      <h1 className="sr-only">Trades</h1>
      <div className="w-full mt-2.5">
        <TradeFilterBar
          variant="trades"
          fullWidth
          accounts={accounts}
          accountFilter={accountFilter}
          onAccountChange={onAccountChange}
          isPro={isPro}
          copyGroups={copyGroups}
          accountTypeFilter={accountTypeFilter}
          onAccountTypeChange={onAccountTypeChange}
          timeframe={timeframe}
          onTimeframeChange={onTimeframeChange}
          customRangeStart={customRangeStart}
          customRangeEnd={customRangeEnd}
          onCustomRangeApply={onCustomRangeApply}
          selectedDate={selectedDate}
          onSelectedDateChange={onSelectedDateChange}
          accountSelectAccessory={
            <Button
              type="button"
              variant="primary"
              size="md"
              onClick={onOpenQuickInput}
              aria-label="Quick Trade"
              className="h-9 w-9 shrink-0 p-0 text-base leading-none"
            >
              <span aria-hidden>+</span>
            </Button>
          }
          leading={
            <div className="flex w-full shrink-0 flex-nowrap items-center justify-center gap-2 md:w-auto">
              {/* Desktop-only Quick Trade button — styled like the Timeframe filter control. */}
              <button
                type="button"
                onClick={onOpenQuickInput}
                className="hidden h-[34px] shrink-0 items-center whitespace-nowrap rounded-lg bg-white/10 px-4 text-sm font-medium text-white transition hover:bg-white/20 md:inline-flex"
              >
                Quick Trade
              </button>

              <button
                type="button"
                onClick={() => onResultFilterChange("all")}
                className={`inline-flex h-[34px] items-center whitespace-nowrap rounded-md px-3 text-sm text-white ${
                  resultFilter === "all"
                    ? "bg-blue-500 hover:bg-blue-600"
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
                  className={`relative flex h-[34px] w-28 cursor-pointer items-center rounded-full px-2 transition
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
                className="order-1 flex-1 h-10 px-3 rounded bg-white/10 hover:bg-white/20 text-sm text-white flex items-center justify-center md:order-3 md:h-[34px] md:flex-none md:rounded-md md:px-3 md:py-0"
              >
                {showAdvanced ? "Hide Advanced" : "Show Advanced"}
              </button>
              <button
                type="button"
                onClick={onTogglePublicOnly}
                className={`order-2 flex-[0.8] h-10 px-2 rounded text-sm font-medium transition flex items-center justify-center md:order-1 md:h-[34px] md:flex-none md:rounded-xl md:px-4 md:py-0
                  ${
                    showPublicOnly
                      ? "bg-blue-500 text-white"
                      : "bg-white/10 text-gray-300 hover:bg-white/20"
                  }`}
              >
                Public
              </button>
              <PerformanceShareButton onClick={onOpenPerformanceShare} />
            </div>
          }
        />
      </div>

      {loading ? (
        <>
          <div
            aria-busy="true"
            aria-label="Loading trade statistics"
            className="mt-2.5 w-full grid grid-cols-2 md:grid-cols-4 gap-2"
          >
            {Array.from({ length: 4 }).map((_, i) => (
              <SkeletonStatsCard key={i} />
            ))}
          </div>
          <div
            aria-busy="true"
            aria-label="Loading trades"
            className="mt-2.5 w-full grid grid-cols-1 md:grid-cols-2 gap-x-4 gap-y-2.5"
          >
            {Array.from({ length: 6 }).map((_, i) => (
              <SkeletonTradesPageTradeCard key={i} />
            ))}
          </div>
        </>
      ) : (
        <>
          <div className="mt-2.5 w-full grid grid-cols-2 md:grid-cols-4 gap-2">
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

          <div className="mt-2.5 w-full grid grid-cols-1 md:grid-cols-2 gap-x-4 gap-y-2.5">
            {displayedTrades.length === 0 ? (
              <div className="md:col-span-2">
                <EmptyState
                  title={
                    hasAnyTrades
                      ? "No Trades Match Your Filters"
                      : "No Trades Yet"
                  }
                  description={
                    hasAnyTrades
                      ? "Try adjusting your account, date range, or result filters to see more trades."
                      : "Start tracking your performance by logging your first trade."
                  }
                  action={
                    hasAnyTrades ? undefined : (
                    <div className="flex flex-wrap items-center justify-center gap-3">
                      <Link
                        href="/app"
                        className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:hover:bg-blue-500"
                      >
                        Add Trade
                      </Link>
                      
                    </div>
                    )
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
                  accounts={Object.values(accountById)}
                  shareProfile={gateProfile}
                  attachedReel={tradeReelsByTradeId[String(trade.id)] ?? null}
                  onOpenReplay={
                    onOpenTradeReplay
                      ? () => onOpenTradeReplay(trade)
                      : undefined
                  }
                  onEdit={onEditTrade}
                  onDelete={onDeleteTrade}
                  onSendClick={onSendTrade}
                  onAnalyze={onAnalyzeTrade}
                  onImageClick={onImageClick}
                />
              ))
            )}
          </div>

          {visibleCount < visibleTradesLength ? (
            <div className="mt-2.5 flex justify-center">
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
      )}
    </>
  )
}

export default memo(TradesPageMainContent)
