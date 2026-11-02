"use client"

import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from "react"
import { createPortal } from "react-dom"
import CustomSelect from "@/app/components/CustomSelect"
import DashboardTimeframePicker from "@/app/components/dashboard/DashboardTimeframePicker"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { useMobileWebSheetDismiss } from "@/lib/useMobileWebSheetDismiss"
import { usePhoneWebDialogFocus } from "@/lib/usePhoneWebDialogFocus"
import { SELECT_FILTER_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import { DASHBOARD_TF_LABEL_FROM_VALUE } from "@/lib/dashboardTimeframeLabels"
import { TRADES_SORT_OPTIONS, type TradesSortKey } from "@/lib/tradesSort"

const MODE_OPTIONS = [
  { label: "All Modes", value: "all" },
  { label: "Live", value: "live" },
  { label: "Funded", value: "funded" },
  { label: "Eval", value: "eval" },
] as const

export type MobileWebTradesFilterSheetProps = {
  open: boolean
  onClose: () => void
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
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  sortBy: TradesSortKey
  onSortByChange: (value: TradesSortKey) => void
}

export default function MobileWebTradesFilterSheet({
  open,
  onClose,
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
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  sortBy,
  onSortByChange,
}: MobileWebTradesFilterSheetProps) {
  const [timeframePickerOpen, setTimeframePickerOpen] = useState(false)
  const dialogRef = useRef<HTMLDivElement>(null)

  useModalScrollLock(open)
  const sheetDismiss = useMobileWebSheetDismiss(onClose)
  usePhoneWebDialogFocus(open, dialogRef)

  useEffect(() => {
    if (!open) {
      setTimeframePickerOpen(false)
      return
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || typeof document === "undefined") return null

  const timeframeLabel = selectedDate.trim()
    ? selectedDate
    : timeframe === "custom" && customRangeStart && customRangeEnd
      ? `${customRangeStart} – ${customRangeEnd}`
      : DASHBOARD_TF_LABEL_FROM_VALUE[timeframe] ?? "All Time"

  return createPortal(
    <div
      className="fixed inset-0 z-[10050] flex items-end justify-center md:hidden"
      role="presentation"
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="mobile-web-trades-filter-title"
        ref={dialogRef}
        className="relative z-10 flex max-h-[min(88svh,640px)] w-full flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl pb-[max(0.75rem,env(safe-area-inset-bottom))]"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="shrink-0" {...sheetDismiss}>
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-white/25" aria-hidden />
        <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
          <h2
            id="mobile-web-trades-filter-title"
            className="text-base font-semibold text-white"
          >
            Filters
          </h2>
          <ModalCloseButton onClick={onClose} />
        </div>
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-y-contain px-4 py-4">
          <section>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]">
              Account
            </h3>
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
              hideManageAccounts={false}
            />
            <div className="mt-2">
              <CustomSelect
                value={accountTypeFilter}
                onChange={onAccountTypeChange}
                className="w-full"
                triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
                aria-label="Account mode"
                options={[...MODE_OPTIONS]}
              />
            </div>
          </section>

          <section>
            <h3
              id="mobile-web-trades-filter-date"
              className="mb-2 text-xs font-semibold uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]"
            >
              Date
            </h3>
            <button
              type="button"
              onClick={() => setTimeframePickerOpen(true)}
              aria-label={`Date, ${timeframeLabel}`}
              className="inline-flex h-11 w-full items-center justify-between rounded-[14px] border border-white/15 bg-white/10 px-3 text-sm font-medium text-white"
            >
              <span className="truncate">{timeframeLabel}</span>
              <span className="text-[color:var(--tt-text-tertiary,#a8b3c2)]" aria-hidden>
                ›
              </span>
            </button>
          </section>

          <section>
            <h3
              id="mobile-web-trades-filter-result"
              className="mb-2 text-xs font-semibold uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]"
            >
              Result
            </h3>
            <div
              className="grid grid-cols-3 gap-2"
              role="group"
              aria-labelledby="mobile-web-trades-filter-result"
            >
              {(
                [
                  { id: "all", label: "All" },
                  { id: "wins", label: "Wins" },
                  { id: "losses", label: "Losses" },
                ] as const
              ).map((option) => (
                <button
                  key={option.id}
                  type="button"
                  onClick={() => onResultFilterChange(option.id)}
                  aria-pressed={resultFilter === option.id}
                  className={`h-11 rounded-[14px] text-sm font-semibold transition ${
                    resultFilter === option.id
                      ? "bg-[#0A6E8A] text-white"
                      : "bg-white/10 text-[color:var(--tt-text-muted,#c0cad6)]"
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
          </section>

          <section>
            <h3
              id="mobile-web-trades-filter-sort"
              className="mb-2 text-xs font-semibold uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]"
            >
              Sort
            </h3>
            <div
              className="space-y-1.5"
              role="group"
              aria-labelledby="mobile-web-trades-filter-sort"
            >
              {TRADES_SORT_OPTIONS.map((option) => (
                <button
                  key={option.key}
                  type="button"
                  onClick={() => onSortByChange(option.key)}
                  aria-pressed={sortBy === option.key}
                  className={`flex h-11 w-full items-center justify-between rounded-[14px] px-3 text-left text-sm font-medium transition ${
                    sortBy === option.key
                      ? "bg-white/15 text-white"
                      : "bg-white/5 text-[color:var(--tt-text-muted,#c0cad6)]"
                  }`}
                >
                  <span>{option.label}</span>
                  {sortBy === option.key ? (
                    <span className="text-[#4EC4E0]" aria-hidden>
                      ✓
                    </span>
                  ) : null}
                </button>
              ))}
            </div>
          </section>

          <section className="space-y-2">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]">
              Visibility
            </h3>
            <button
              type="button"
              onClick={onTogglePublicOnly}
              aria-pressed={showPublicOnly}
              className={`flex h-11 w-full items-center justify-between rounded-[14px] px-3 text-sm font-medium ${
                showPublicOnly
                  ? "bg-[#0A6E8A] text-white"
                  : "bg-white/5 text-[color:var(--tt-text-muted,#c0cad6)]"
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
                onOpenPerformanceShare()
                onClose()
              }}
              className="flex h-11 w-full items-center rounded-[14px] bg-white/5 px-3 text-sm font-medium text-[color:var(--tt-text,#f0f3f6)]"
            >
              Share performance
            </button>
          </section>

          <button
            type="button"
            onClick={onClose}
            className="min-h-11 w-full rounded-[14px] bg-[#0A6E8A] py-3 text-sm font-semibold text-white"
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
