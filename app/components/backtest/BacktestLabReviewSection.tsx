"use client"

import { useMemo } from "react"
import CustomSelect from "@/app/components/CustomSelect"
import {
  backtestTradeHasIncompleteDocumentation,
  isBacktestTradeNeedsReview,
} from "@/lib/backtestLabReview"
import type { BacktestLabFilterState } from "@/lib/backtestLabFilters"
import BacktestLabSessionGroups from "@/app/components/backtest/BacktestLabSessionGroups"
import BacktestLabReviewTradeCard from "@/app/components/backtest/BacktestLabReviewTradeCard"
import type { BacktestLabStrategyGroup } from "@/lib/backtestLabFilters"
import { BACKTEST_LAB_SELECT_PROPS } from "@/lib/backtestLabUiStyles"

const REVIEW_VIEW_OPTIONS = [
  { label: "All trades", value: "list" as const },
  { label: "Grouped sessions", value: "groups" as const },
]

type BacktestLabReviewSectionProps = {
  trades: Record<string, unknown>[]
  filters: BacktestLabFilterState
  onFiltersChange: (next: BacktestLabFilterState) => void
  strategyGroups: BacktestLabStrategyGroup[]
  shareProfile?: { referral_code?: string | null } | null
  onEdit: (trade: Record<string, unknown>) => void
  onDelete: (tradeId: string) => void
  onSendClick: (trade: Record<string, unknown>) => void
  onAnalyze?: (trade: Record<string, unknown>) => void
  onImageClick: (imageUrl: string) => void
  onToggleReviewed: (tradeId: string, reviewed: boolean) => void
  reviewBusyId?: string | null
  viewMode: "list" | "groups"
  onViewModeChange: (mode: "list" | "groups") => void
}

export default function BacktestLabReviewSection({
  trades,
  filters,
  onFiltersChange,
  strategyGroups,
  shareProfile,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
  onToggleReviewed,
  reviewBusyId,
  viewMode,
  onViewModeChange,
}: BacktestLabReviewSectionProps) {
  const stats = useMemo(() => {
    let needsReview = 0
    let incomplete = 0
    for (const trade of trades) {
      if (isBacktestTradeNeedsReview(trade)) needsReview += 1
      if (backtestTradeHasIncompleteDocumentation(trade)) incomplete += 1
    }
    return { needsReview, incomplete }
  }, [trades])

  const patch = (partial: Partial<BacktestLabFilterState>) => {
    onFiltersChange({ ...filters, ...partial })
  }

  const needsReviewFilterActive =
    filters.review === "needs_review" && filters.documentation === "all"
  const incompleteDocsFilterActive =
    filters.documentation === "incomplete" && filters.review === "all"

  return (
    <div className="space-y-4 pb-12">
      <div className="backtest-lab-section-card backtest-lab-review-queue">
        <h2 className="backtest-lab-review-title text-lg font-semibold">
          Review queue
        </h2>
        <p className="backtest-lab-review-muted mt-1 text-sm">
          Mark trades reviewed when journaling is complete. Incomplete documentation
          (missing strategy, notes, or screenshot) is tracked separately from the
          review flag.
        </p>
        <div className="mt-3 flex flex-wrap gap-3 text-sm font-medium">
          <span className="backtest-lab-review-stat-needs">
            {stats.needsReview} need review
          </span>
          <span className="backtest-lab-review-stat-incomplete">
            {stats.incomplete} incomplete docs
          </span>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            aria-pressed={needsReviewFilterActive}
            onClick={() =>
              patch({
                review: "needs_review",
                documentation: "all",
              })
            }
            className="backtest-lab-review-filter-btn backtest-lab-review-filter-btn--needs"
          >
            Show needs review
          </button>
          <button
            type="button"
            aria-pressed={incompleteDocsFilterActive}
            onClick={() =>
              patch({
                documentation: "incomplete",
                review: "all",
              })
            }
            className="backtest-lab-review-filter-btn backtest-lab-review-filter-btn--incomplete"
          >
            Show incomplete documentation
          </button>
          <button
            type="button"
            onClick={() =>
              patch({
                review: "all",
                documentation: "all",
              })
            }
            className="backtest-lab-review-filter-btn backtest-lab-review-filter-btn--neutral"
          >
            Clear review filters
          </button>
        </div>
      </div>

      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <h2 className="backtest-lab-review-title text-xl font-semibold">
          Backtest trades
        </h2>
        <CustomSelect
          value={viewMode}
          onChange={(value) => onViewModeChange(value as "list" | "groups")}
          {...BACKTEST_LAB_SELECT_PROPS}
          className="w-full sm:w-52"
          options={REVIEW_VIEW_OPTIONS}
        />
      </div>

      {viewMode === "groups" ? (
        <BacktestLabSessionGroups
          trades={trades}
          strategyGroups={strategyGroups}
          shareProfile={shareProfile}
          onEdit={onEdit}
          onDelete={onDelete}
          onSendClick={onSendClick}
          onAnalyze={onAnalyze}
          onImageClick={onImageClick}
          onToggleReviewed={onToggleReviewed}
          reviewBusyId={reviewBusyId}
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {trades.map((trade) => (
            <BacktestLabReviewTradeCard
              key={String(trade.id)}
              trade={trade as Record<string, unknown> & { id: string }}
              shareProfile={shareProfile}
              onEdit={onEdit}
              onDelete={onDelete}
              onSendClick={onSendClick}
              onAnalyze={onAnalyze}
              onImageClick={onImageClick}
              onToggleReviewed={onToggleReviewed}
              reviewBusy={reviewBusyId === String(trade.id)}
            />
          ))}
          {trades.length === 0 ? (
            <p className="backtest-lab-review-muted text-center lg:col-span-2">
              No backtest trades match these filters.
            </p>
          ) : null}
        </div>
      )}
    </div>
  )
}
