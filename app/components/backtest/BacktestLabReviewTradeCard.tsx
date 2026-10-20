"use client"

import TradesPageTradeCard from "@/app/components/TradesPageTradeCard"
import BacktestLabReflectionPreview from "@/app/components/backtest/BacktestLabReflectionPreview"
import {
  backtestTradeDocumentationGaps,
  formatBacktestDocumentationGapLabels,
  isBacktestTradeReviewed,
  isExplicitlyUnreviewedTrade,
} from "@/lib/backtestLabReview"

export type BacktestLabReviewTradeCardProps = {
  trade: Record<string, unknown> & { id: string }
  shareProfile?: { referral_code?: string | null } | null
  onEdit: (trade: Record<string, unknown>) => void
  onDelete: (tradeId: string) => void
  onSendClick: (trade: Record<string, unknown>) => void
  onAnalyze?: (trade: Record<string, unknown>) => void
  onImageClick: (imageUrl: string) => void
  onToggleReviewed: (tradeId: string, reviewed: boolean) => void
  reviewBusy?: boolean
}

export default function BacktestLabReviewTradeCard({
  trade,
  shareProfile,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
  onToggleReviewed,
  reviewBusy = false,
}: BacktestLabReviewTradeCardProps) {
  const reviewed = isBacktestTradeReviewed(trade)
  const explicitUnreviewed = isExplicitlyUnreviewedTrade(trade)
  const gaps = backtestTradeDocumentationGaps(trade)
  const gapLabel = formatBacktestDocumentationGapLabels(gaps)

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2 px-0.5">
        {reviewed ? (
          <span className="rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-emerald-300">
            Reviewed
          </span>
        ) : explicitUnreviewed ? (
          <span className="backtest-lab-review-badge backtest-lab-review-badge--needs">
            Needs review
          </span>
        ) : (
          <span className="backtest-lab-review-badge backtest-lab-review-badge--neutral">
            Not marked reviewed
          </span>
        )}
        {gaps.length > 0 ? (
          <span className="backtest-lab-review-badge backtest-lab-review-badge--incomplete">
            Incomplete: {gapLabel}
          </span>
        ) : null}
        <div className="ml-auto flex flex-wrap gap-2">
          <button
            type="button"
            disabled={reviewBusy}
            onClick={() => onEdit(trade)}
            className="rounded-lg border border-white/15 bg-white/5 px-2.5 py-1 text-xs font-medium text-white hover:bg-white/10 disabled:opacity-50"
          >
            Edit & reflect
          </button>
          {reviewed ? (
            <button
              type="button"
              disabled={reviewBusy}
              onClick={() => onToggleReviewed(String(trade.id), false)}
              className="rounded-lg border border-white/15 bg-white/5 px-2.5 py-1 text-xs font-medium text-gray-200 hover:bg-white/10 disabled:opacity-50"
            >
              Mark needs review
            </button>
          ) : (
            <button
              type="button"
              disabled={reviewBusy}
              onClick={() => onToggleReviewed(String(trade.id), true)}
              className="rounded-lg bg-blue-600 px-2.5 py-1 text-xs font-semibold text-white hover:bg-blue-500 disabled:opacity-50"
            >
              Mark reviewed
            </button>
          )}
        </div>
      </div>

      <BacktestLabReflectionPreview trade={trade} />

      <TradesPageTradeCard
        trade={trade}
        shareProfile={shareProfile}
        onEdit={onEdit}
        onDelete={onDelete}
        onSendClick={onSendClick}
        onAnalyze={onAnalyze}
        onImageClick={onImageClick}
      />
    </div>
  )
}
