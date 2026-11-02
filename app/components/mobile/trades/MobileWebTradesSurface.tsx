"use client"

import Link from "next/link"
import { useMemo, useState, type Dispatch, type SetStateAction } from "react"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import EmptyState from "@/app/components/ui/EmptyState"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import type { TradesPageListItem } from "@/lib/copyTradePresentation"
import {
  buildMobileWebTradesChips,
  sortTradeListItemsForMobileWeb,
  tradeListItemMatchesMobileWebSearch,
  type MobileWebTradesChipId,
} from "@/lib/mobileWebTradesPresentation"
import type { TradesSortKey } from "@/lib/tradesSort"
import { Search, SlidersHorizontal } from "lucide-react"
import MobileWebNetworkNotice from "@/app/components/mobile/MobileWebNetworkNotice"
import MobileWebTradeJournalCard from "./MobileWebTradeJournalCard"
import MobileWebTradesFilterSheet from "./MobileWebTradesFilterSheet"

type MobileWebTradesSurfaceProps = {
  loading: boolean
  accounts: Array<{ value: string; label: string; accountType?: string | null }>
  accountFilter: string
  onAccountChange: (value: string) => void
  isPro?: boolean
  copyGroups?: CopyTradingGroup[]
  onAccountPickerOpen?: () => void
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
  onOpenQuickInput: () => void
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  sortBy: TradesSortKey
  onSortByChange: (value: TradesSortKey) => void
  displayedTradeItems: TradesPageListItem[]
  visibleTradesLength: number
  hasAnyTrades: boolean
  visibleCount: number
  accountById: Record<string, any>
  onOpenTrade: (trade: any) => void
  onEditTrade: (trade: any) => void
  onDeleteTrade: (tradeId: string) => void
  onSendTrade: (trade: any) => void
  onAnalyzeTrade?: (trade: any) => void
  onImageClick: (imageUrl: string) => void
  onLoadMore: () => void
  onImportCsv: () => void
  selectedTradeId?: string | null
  loadError?: string | null
  onRetryLoad?: () => void
  retryingLoad?: boolean
}

export default function MobileWebTradesSurface({
  loading,
  accounts,
  accountFilter,
  onAccountChange,
  isPro = false,
  copyGroups = [],
  onAccountPickerOpen,
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
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  sortBy,
  onSortByChange,
  displayedTradeItems,
  visibleTradesLength,
  hasAnyTrades,
  visibleCount,
  accountById,
  onOpenTrade,
  onEditTrade,
  onDeleteTrade,
  onSendTrade,
  onAnalyzeTrade,
  onImageClick,
  onLoadMore,
  onImportCsv,
  selectedTradeId = null,
  loadError = null,
  onRetryLoad,
  retryingLoad = false,
}: MobileWebTradesSurfaceProps) {
  const [search, setSearch] = useState("")
  const [filterOpen, setFilterOpen] = useState(false)

  const accountLabel = accounts.find((account) => account.value === accountFilter)
    ?.label

  const chips = useMemo(
    () =>
      buildMobileWebTradesChips({
        search,
        accountFilter,
        accountLabel,
        accountTypeFilter,
        timeframe,
        selectedDate,
        customRangeStart,
        customRangeEnd,
        resultFilter,
        showPublicOnly,
        sortBy,
      }),
    [
      accountFilter,
      accountLabel,
      accountTypeFilter,
      customRangeEnd,
      customRangeStart,
      resultFilter,
      search,
      selectedDate,
      showPublicOnly,
      sortBy,
      timeframe,
    ]
  )

  const items = useMemo(() => {
    const matched = displayedTradeItems.filter((item) =>
      tradeListItemMatchesMobileWebSearch(item, search)
    )
    return sortTradeListItemsForMobileWeb(matched, sortBy)
  }, [displayedTradeItems, search, sortBy])

  function removeChip(id: MobileWebTradesChipId) {
    switch (id) {
      case "search":
        setSearch("")
        break
      case "account":
        onAccountChange("all")
        break
      case "mode":
        onAccountTypeChange("all")
        break
      case "timeframe":
        onTimeframeChange("all")
        onSelectedDateChange("")
        break
      case "result":
        onResultFilterChange("all")
        break
      case "public":
        if (showPublicOnly) onTogglePublicOnly()
        break
      case "sort":
        onSortByChange("newest")
        break
      default:
        break
    }
  }

  return (
    <div className="md:hidden mt-1 space-y-2.5">
      <label className="relative block">
        <span className="sr-only">Search trades</span>
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
          strokeWidth={2}
          aria-hidden
        />
        <input
          type="search"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search trades…"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="search"
          className="h-11 w-full rounded-[14px] border border-white/10 bg-white/10 py-2.5 pl-10 pr-3 text-[15px] text-[color:var(--tt-text,#f0f3f6)] placeholder:text-[color:var(--tt-text-placeholder,#939dab)] focus:outline-none focus:ring-2 focus:ring-[#4EC4E0]/40"
        />
      </label>

      <div className="flex items-center gap-2">
        <div className="min-w-0 flex-1">
          <TradeAccountPicker
            accounts={[]}
            isPro={isPro}
            copyGroups={copyGroups}
            onPickerOpen={onAccountPickerOpen}
            filterValue={accountFilter}
            filterOptions={accounts}
            onFilterChange={onAccountChange}
            filterPlaceholder="All Accounts"
            showExternalCreateButton={false}
            triggerClassName="inline-flex min-h-11 w-full max-w-full items-center justify-between rounded-full bg-white/10 px-3 text-[15px] font-medium text-[color:var(--tt-text,#f0f3f6)]"
          />
        </div>
        <button
          type="button"
          onClick={() => setFilterOpen(true)}
          className="relative inline-flex min-h-11 shrink-0 items-center gap-1 rounded-full bg-white/10 px-3.5 text-[15px] font-medium text-[color:var(--tt-text,#f0f3f6)]"
          aria-label="Filters"
        >
          <SlidersHorizontal className="h-3.5 w-3.5" strokeWidth={2.25} aria-hidden />
          Filters
          {chips.length > 0 ? (
            <span
              className="absolute -right-0.5 -top-0.5 h-1.5 w-1.5 rounded-full bg-[#4EC4E0]"
              aria-hidden
            />
          ) : null}
        </button>
      </div>

      {chips.length > 0 ? (
        <div className="tt-mobile-web-hscroll flex gap-1.5 overflow-x-auto pb-0.5 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {chips.map((chip) => (
            <button
              key={chip.id}
              type="button"
              onClick={() => removeChip(chip.id)}
              className="tt-mobile-web-hit-y inline-flex shrink-0 items-center gap-1 rounded-full bg-white/10 px-2.5 py-1.5 text-[12px] text-white"
            >
              {chip.title}
              <span aria-hidden className="text-[color:var(--tt-text-tertiary,#a8b3c2)]">
                ×
              </span>
            </button>
          ))}
        </div>
      ) : null}

      {loadError && hasAnyTrades ? (
        <MobileWebNetworkNotice
          variant="inline"
          message={loadError}
          onRetry={onRetryLoad}
          retrying={retryingLoad}
        />
      ) : null}

      {loading && !(loadError && !hasAnyTrades) ? (
        <div className="space-y-2" aria-busy="true" aria-label="Loading trades">
          {Array.from({ length: 4 }).map((_, index) => (
            <div
              key={index}
              className="h-28 animate-pulse rounded-[18px] border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : loadError && items.length === 0 && !hasAnyTrades ? (
        <MobileWebNetworkNotice
          variant="panel"
          title="Couldn't load trades"
          message={loadError}
          onRetry={onRetryLoad}
          retrying={retryingLoad}
        />
      ) : items.length === 0 ? (
        <EmptyState
          title={
            hasAnyTrades
              ? search.trim()
                ? "No trades match these filters."
                : "No trades match these filters."
              : "No trades yet"
          }
          description={
            hasAnyTrades
              ? undefined
              : "Log a trade to start building your journal."
          }
          action={
            hasAnyTrades ? (
              <button
                type="button"
                onClick={() => {
                  setSearch("")
                  onAccountChange("all")
                  onAccountTypeChange("all")
                  onTimeframeChange("all")
                  onSelectedDateChange("")
                  onResultFilterChange("all")
                  onSortByChange("newest")
                  if (showPublicOnly) onTogglePublicOnly()
                }}
                className="rounded-[14px] bg-[#0A6E8A] px-4 py-2.5 text-sm font-semibold text-white"
              >
                Clear Filters
              </button>
            ) : (
              <div className="flex flex-wrap items-center justify-center gap-2">
                <button
                  type="button"
                  onClick={onOpenQuickInput}
                  className="rounded-[14px] bg-[#0A6E8A] px-4 py-2.5 text-sm font-semibold text-white"
                >
                  Add Trade
                </button>
                <button
                  type="button"
                  onClick={onImportCsv}
                  className="rounded-[14px] border border-white/20 bg-white/10 px-4 py-2.5 text-sm font-semibold text-white"
                >
                  Import CSV
                </button>
                <Link
                  href="/settings#broker-integrations"
                  className="rounded-[14px] border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-semibold text-gray-100"
                >
                  Connect Broker
                </Link>
              </div>
            )
          }
          className="py-10"
        />
      ) : (
        <div className="space-y-2">
          <p className="px-0.5 text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">
            {items.length.toLocaleString()}{" "}
            {items.length === 1 ? "trade" : "trades"}
            <span className="text-[color:var(--tt-text-tertiary,#a8b3c2)]">
              {" "}
              • Tap a trade to see more information
            </span>
          </p>
          {items.map((item) => {
            const trade =
              item.kind === "copyGroup" ? item.representative : item.trade
            const tradeId = String(trade.id ?? "")
            return (
              <div
                key={item.kind === "copyGroup" ? item.batchKey : tradeId}
              >
                <MobileWebTradeJournalCard
                  trade={trade}
                  copyGroupMembers={
                    item.kind === "copyGroup" ? item.members : undefined
                  }
                  copyModeSummary={
                    item.kind === "copyGroup" ? item.modeSummary : null
                  }
                  accountRow={accountById[String(trade.account_id ?? "")]}
                  selected={selectedTradeId === tradeId}
                  onOpen={onOpenTrade}
                  onEdit={onEditTrade}
                  onDelete={onDeleteTrade}
                  onSendClick={onSendTrade}
                  onAnalyze={onAnalyzeTrade}
                  onImageClick={onImageClick}
                />
              </div>
            )
          })}
        </div>
      )}

      {!loading && visibleCount < visibleTradesLength ? (
        <div className="flex justify-center pt-1">
          <button
            type="button"
            onClick={onLoadMore}
            className="min-h-11 rounded-[14px] bg-[#0A6E8A] px-4 text-sm font-semibold text-white"
          >
            Load More
          </button>
        </div>
      ) : null}

      <MobileWebTradesFilterSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        accounts={accounts}
        accountFilter={accountFilter}
        onAccountChange={onAccountChange}
        isPro={isPro}
        copyGroups={copyGroups}
        onAccountPickerOpen={onAccountPickerOpen}
        accountTypeFilter={accountTypeFilter}
        onAccountTypeChange={onAccountTypeChange}
        timeframe={timeframe}
        onTimeframeChange={onTimeframeChange}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCustomRangeApply={onCustomRangeApply}
        selectedDate={selectedDate}
        onSelectedDateChange={onSelectedDateChange}
        resultFilter={resultFilter}
        onResultFilterChange={onResultFilterChange}
        showPublicOnly={showPublicOnly}
        onTogglePublicOnly={onTogglePublicOnly}
        onOpenPerformanceShare={onOpenPerformanceShare}
        sortBy={sortBy}
        onSortByChange={onSortByChange}
      />
    </div>
  )
}
