"use client"

import { useEffect, useState, type Dispatch, type SetStateAction } from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import CustomSelect from "@/app/components/CustomSelect"
import DashboardTimeframePicker from "@/app/components/dashboard/DashboardTimeframePicker"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { SELECT_FILTER_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import {
  TRADES_SORT_OPTIONS,
  type TradesSortKey,
} from "@/lib/tradesSort"
import { hapticLight } from "@/lib/nativeHaptics"

const MODE_OPTIONS = [
  { label: "All Modes", value: "all" },
  { label: "Live", value: "live" },
  { label: "Funded", value: "funded" },
  { label: "Eval", value: "eval" },
] as const

export type NativeIosTradesFilterSheetProps = {
  open: boolean
  onClose: () => void
  accounts: Array<{ value: string; label: string; accountType?: string | null }>
  accountFilter: string
  onAccountChange: (value: string) => void
  isPro?: boolean
  copyGroups?: CopyTradingGroup[]
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
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  showAdvanced: boolean
  onToggleAdvanced: () => void
  onOpenPerformanceShare: () => void
  sortBy: TradesSortKey
  onSortByChange: (value: TradesSortKey) => void
}

/**
 * Native bottom sheet for Trades filters / timeframe / sort.
 * Wires existing page state — no new filter semantics.
 */
export default function NativeIosTradesFilterSheet({
  open,
  onClose,
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
  showPublicOnly,
  onTogglePublicOnly,
  showAdvanced,
  onToggleAdvanced,
  onOpenPerformanceShare,
  sortBy,
  onSortByChange,
}: NativeIosTradesFilterSheetProps) {
  const [timeframePickerOpen, setTimeframePickerOpen] = useState(false)

  useModalScrollLock(open)

  useEffect(() => {
    if (!open) {
      setTimeframePickerOpen(false)
      return
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || typeof document === "undefined") return null

  const timeframeLabel =
    selectedDate?.trim()
      ? selectedDate
      : timeframe === "custom" && customRangeStart && customRangeEnd
        ? `${customRangeStart} – ${customRangeEnd}`
        : timeframe === "daily"
          ? "Today"
          : timeframe === "weekly"
            ? "This Week"
            : timeframe === "monthly"
              ? "This Month"
              : timeframe === "yearly"
                ? "This Year"
                : timeframe === "custom"
                  ? "Custom"
                  : "All Time"

  return createPortal(
    <div
      className="fixed inset-0 z-[10050] flex items-end justify-center"
      role="presentation"
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="native-trades-filter-title"
        className="relative z-10 flex max-h-[min(88svh,640px)] w-full flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl pb-[var(--safe-area-bottom)]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-white/25" aria-hidden />
        <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
          <h2
            id="native-trades-filter-title"
            className="text-base font-semibold text-white"
          >
            Filters
          </h2>
          <ModalCloseButton onClick={onClose} />
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-4 py-4">
          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Account
            </p>
            <TradeAccountPicker
              accounts={[]}
              isPro={isPro}
              copyGroups={copyGroups}
              filterValue={accountFilter}
              filterOptions={accounts}
              onFilterChange={onAccountChange}
              filterPlaceholder="All Accounts"
              showExternalCreateButton={false}
              hideManageAccounts={false}
            />
            <div className="mt-2">
              <CustomSelect
                value={accountTypeFilter}
                onChange={onAccountTypeChange}
                className="w-full"
                triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
                options={[...MODE_OPTIONS]}
              />
            </div>
          </section>

          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Timeframe
            </p>
            <button
              type="button"
              onClick={() => {
                hapticLight("timeframe")
                setTimeframePickerOpen(true)
              }}
              className="inline-flex h-10 w-full items-center justify-between rounded-xl border border-white/15 bg-white/10 px-3 text-sm font-medium text-white"
            >
              <span className="truncate">{timeframeLabel}</span>
              <span className="text-white/50" aria-hidden>
                ›
              </span>
            </button>
          </section>

          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Result
            </p>
            <div className="grid grid-cols-3 gap-2">
              {(
                [
                  { id: "all", label: "All" },
                  { id: "wins", label: "Wins" },
                  { id: "losses", label: "Losses" },
                ] as const
              ).map((opt) => (
                <button
                  key={opt.id}
                  type="button"
                  onClick={() => {
                    hapticLight("result-filter")
                    onResultFilterChange(opt.id)
                  }}
                  className={`h-10 rounded-xl text-sm font-semibold transition ${
                    resultFilter === opt.id
                      ? "bg-blue-500 text-white"
                      : "bg-white/10 text-white/70"
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </section>

          <section>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Sort By
            </p>
            <div className="space-y-1.5">
              {TRADES_SORT_OPTIONS.map((opt) => (
                <button
                  key={opt.key}
                  type="button"
                  onClick={() => {
                    hapticLight("sort")
                    onSortByChange(opt.key)
                  }}
                  className={`flex h-11 w-full items-center justify-between rounded-xl px-3 text-left text-sm font-medium transition ${
                    sortBy === opt.key
                      ? "bg-white/15 text-white"
                      : "bg-white/5 text-white/75 active:bg-white/10"
                  }`}
                >
                  <span>{opt.label}</span>
                  {sortBy === opt.key ? (
                    <span className="text-blue-300" aria-hidden>
                      ✓
                    </span>
                  ) : null}
                </button>
              ))}
            </div>
          </section>

          <section className="space-y-2">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-white/45">
              Options
            </p>
            <button
              type="button"
              onClick={() => {
                hapticLight("public")
                onTogglePublicOnly()
              }}
              className={`flex h-11 w-full items-center justify-between rounded-xl px-3 text-sm font-medium ${
                showPublicOnly ? "bg-blue-500/90 text-white" : "bg-white/5 text-white/80"
              }`}
            >
              <span>Public trades only</span>
              <span className="text-xs opacity-80">
                {showPublicOnly ? "On" : "Off"}
              </span>
            </button>
            <button
              type="button"
              onClick={() => {
                hapticLight("advanced")
                onToggleAdvanced()
              }}
              className={`flex h-11 w-full items-center justify-between rounded-xl px-3 text-sm font-medium ${
                showAdvanced ? "bg-white/15 text-white" : "bg-white/5 text-white/80"
              }`}
            >
              <span>Show advanced fields</span>
              <span className="text-xs opacity-80">
                {showAdvanced ? "On" : "Off"}
              </span>
            </button>
            <button
              type="button"
              onClick={() => {
                hapticLight("share")
                onOpenPerformanceShare()
                onClose()
              }}
              className="flex h-11 w-full items-center rounded-xl bg-white/5 px-3 text-sm font-medium text-white/80 active:bg-white/10"
            >
              Share performance
            </button>
          </section>

          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-xl bg-blue-500 py-3 text-sm font-semibold text-white"
          >
            Done
          </button>
        </div>
      </div>

      <DashboardTimeframePicker
        open={timeframePickerOpen}
        onClose={() => setTimeframePickerOpen(false)}
        presentation="sheet"
        timeframe={timeframe}
        onTimeframeChange={onTimeframeChange}
        selectedDate={selectedDate}
        onSelectedDateChange={onSelectedDateChange}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCustomRangeApply={onCustomRangeApply}
      />
    </div>,
    document.body
  )
}
