"use client"

import CustomSelect from "@/app/components/CustomSelect"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  BACKTEST_LAB_FILTER_ALL,
  BACKTEST_LAB_NO_STRATEGY,
  normalizeBacktestLabFilterDate,
  type BacktestLabFilterState,
  type BacktestLabResultFilter,
  type BacktestLabStrategyGroup,
} from "@/lib/backtestLabFilters"
import {
  BACKTEST_LAB_DATE_FIELD_CLASS,
  BACKTEST_LAB_SELECT_PROPS,
} from "@/lib/backtestLabUiStyles"
import { formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"

export type BacktestLabToolbarProps = {
  filters: BacktestLabFilterState
  onFiltersChange: (next: BacktestLabFilterState) => void
  accountOptions: Array<{ value: string; label: string }>
  strategyGroups: BacktestLabStrategyGroup[]
  tickerOptions: string[]
  onLogTrade: () => void
  onShare: () => void
}

const RESULT_OPTIONS: { label: string; value: BacktestLabResultFilter }[] = [
  { label: "All results", value: "all" },
  { label: "Wins only", value: "wins" },
  { label: "Losses only", value: "losses" },
]

const REVIEW_OPTIONS = [
  { label: "All review states", value: "all" as const },
  { label: "Reviewed", value: "reviewed" as const },
  { label: "Needs review", value: "needs_review" as const },
]

const DOCUMENTATION_OPTIONS = [
  { label: "All documentation", value: "all" as const },
  { label: "Incomplete only", value: "incomplete" as const },
]

export default function BacktestLabToolbar({
  filters,
  onFiltersChange,
  accountOptions,
  strategyGroups,
  tickerOptions,
  onLogTrade,
  onShare,
}: BacktestLabToolbarProps) {
  const patch = (partial: Partial<BacktestLabFilterState>) => {
    const next = { ...filters, ...partial }
    if ("dateStart" in partial) {
      next.dateStart = normalizeBacktestLabFilterDate(partial.dateStart)
    }
    if ("dateEnd" in partial) {
      next.dateEnd = normalizeBacktestLabFilterDate(partial.dateEnd)
    }
    onFiltersChange(next)
  }

  const strategySelectOptions = [
    { label: "All strategies", value: BACKTEST_LAB_FILTER_ALL },
    { label: "No strategy label", value: BACKTEST_LAB_NO_STRATEGY },
    ...strategyGroups
      .filter((g) => g.key !== BACKTEST_LAB_NO_STRATEGY)
      .map((g) => ({ label: g.label, value: g.key })),
  ]

  return (
    <div className="mb-4 space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <button
          type="button"
          onClick={onLogTrade}
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-400/60"
        >
          Log Backtest Trade
        </button>
        <button
          type="button"
          onClick={onShare}
          className="rounded-lg border border-[var(--tt-bl-card-border)] bg-[var(--tt-bl-card-bg)] px-4 py-2 text-sm font-medium text-[var(--tt-bl-control-text)] hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-400/40"
          title="Share performance"
          aria-label="Share performance"
        >
          Share
        </button>
      </div>

      <div className="backtest-lab-filter-grid">
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.accountId}
          onChange={(value) => patch({ accountId: value })}
          aria-label="Backtest account"
          options={[
            { label: "All backtest accounts", value: BACKTEST_LAB_FILTER_ALL },
            ...accountOptions,
          ]}
        />
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.strategy}
          onChange={(value) => patch({ strategy: value })}
          aria-label="Strategy"
          options={strategySelectOptions}
        />
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.ticker}
          onChange={(value) => patch({ ticker: value })}
          aria-label="Instrument"
          options={[
            { label: "All instruments", value: BACKTEST_LAB_FILTER_ALL },
            ...tickerOptions.map((t) => ({ label: t, value: t })),
          ]}
        />
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.result}
          onChange={(value) =>
            patch({ result: value as BacktestLabResultFilter })
          }
          aria-label="Trade result"
          options={RESULT_OPTIONS}
        />
        <div className="backtest-lab-filter-span-2 flex min-w-0 items-center gap-2">
          <NativeDateInput
            value={normalizeBacktestLabFilterDate(filters.dateStart)}
            onChange={(e) => patch({ dateStart: e.target.value })}
            placeholder="From date"
            aria-label="From date"
            className={`${BACKTEST_LAB_DATE_FIELD_CLASS} min-w-0 flex-1`}
          />
          <span
            className="backtest-lab-date-range-to shrink-0 text-sm font-medium"
            aria-hidden
          >
            To
          </span>
          <NativeDateInput
            value={normalizeBacktestLabFilterDate(filters.dateEnd)}
            onChange={(e) => patch({ dateEnd: e.target.value })}
            placeholder="End date"
            aria-label="To date"
            className={`${BACKTEST_LAB_DATE_FIELD_CLASS} min-w-0 flex-1`}
          />
        </div>
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.review}
          onChange={(value) => patch({ review: value as typeof filters.review })}
          aria-label="Review state"
          options={REVIEW_OPTIONS}
        />
        <CustomSelect
          {...BACKTEST_LAB_SELECT_PROPS}
          value={filters.documentation}
          onChange={(value) =>
            patch({ documentation: value as typeof filters.documentation })
          }
          aria-label="Documentation completeness"
          options={DOCUMENTATION_OPTIONS}
        />
      </div>
    </div>
  )
}

export function buildBacktestAccountFilterOptions(
  trades: readonly Record<string, unknown>[],
  accounts: readonly Record<string, unknown>[]
): Array<{ value: string; label: string }> {
  const byId = new Map<string, string>()
  for (const account of accounts) {
    const category = String(account.category ?? "").trim()
    const mode = String(account.mode ?? "").trim().toLowerCase()
    if (category !== "Backtest" && mode !== "backtest") continue
    const id = String(account.id ?? "").trim()
    if (!id) continue
    const label = formatTradeAccountNameSizeLine(
      { account_name: account.name, account_size: account.account_size },
      account as { name?: string | null; account_size?: string | null }
    )
    byId.set(id, label || String(account.name ?? "Backtest account"))
  }
  for (const trade of trades) {
    const id = String(trade.account_id ?? "").trim()
    if (!id || byId.has(id)) continue
    const label = formatTradeAccountNameSizeLine(trade as never, null)
    byId.set(id, label || "Backtest account")
  }
  return Array.from(byId.entries())
    .map(([value, label]) => ({ value, label }))
    .sort((a, b) => a.label.localeCompare(b.label))
}
