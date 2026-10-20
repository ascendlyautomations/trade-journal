"use client"

import { useMemo, useState, type ReactNode } from "react"
import CustomSelect from "@/app/components/CustomSelect"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import {
  buildBacktestLabSessionGroups,
  type BacktestLabSessionGroup,
  type BacktestLabSessionGroupMode,
} from "@/lib/backtestLabSessions"
import type { BacktestLabStrategyGroup } from "@/lib/backtestLabFilters"
import BacktestLabReviewTradeCard from "@/app/components/backtest/BacktestLabReviewTradeCard"
import { BACKTEST_LAB_SELECT_PROPS } from "@/lib/backtestLabUiStyles"

const MODE_OPTIONS: { label: string; value: BacktestLabSessionGroupMode }[] = [
  { label: "Trading date", value: "date" },
  { label: "Strategy", value: "strategy" },
  { label: "Instrument", value: "instrument" },
]

type BacktestLabSessionGroupsProps = {
  trades: Record<string, unknown>[]
  strategyGroups: BacktestLabStrategyGroup[]
  shareProfile?: { referral_code?: string | null } | null
  onEdit: (trade: Record<string, unknown>) => void
  onDelete: (tradeId: string) => void
  onSendClick: (trade: Record<string, unknown>) => void
  onAnalyze?: (trade: Record<string, unknown>) => void
  onImageClick: (imageUrl: string) => void
  onToggleReviewed: (tradeId: string, reviewed: boolean) => void
  reviewBusyId?: string | null
}

function SessionGroupPanel({
  group,
  expanded,
  onToggle,
  children,
}: {
  group: BacktestLabSessionGroup
  expanded: boolean
  onToggle: () => void
  children: ReactNode
}) {
  const winRate =
    group.winRate != null ? `${group.winRate.toFixed(1)}%` : "—"
  const pnlClass =
    group.netPnl > 0
      ? "text-emerald-400"
      : group.netPnl < 0
        ? "text-red-400"
        : "text-gray-200"

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 backdrop-blur-md">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full flex-wrap items-center gap-x-4 gap-y-2 px-3 py-3 text-left hover:bg-white/5"
      >
        <span className="min-w-0 flex-1 font-semibold text-white">
          {group.label}
        </span>
        <span className="text-xs text-gray-400">{group.totalTrades} trades</span>
        <span className={`text-sm font-semibold tabular-nums ${pnlClass}`}>
          {formatPnlCurrency(group.netPnl, {
            minimumFractionDigits: 0,
            maximumFractionDigits: 2,
          })}
        </span>
        <span className="text-xs text-gray-400">WR {winRate}</span>
        <span className="text-xs text-gray-400">
          Avg R {formatRR(group.avgRR)}
        </span>
        <span className="text-xs text-blue-300">{expanded ? "Hide" : "Show"}</span>
      </button>
      {expanded ? (
        <div className="space-y-4 border-t border-white/10 p-3">{children}</div>
      ) : null}
    </div>
  )
}

export default function BacktestLabSessionGroups({
  trades,
  strategyGroups,
  shareProfile,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
  onToggleReviewed,
  reviewBusyId,
}: BacktestLabSessionGroupsProps) {
  const [mode, setMode] = useState<BacktestLabSessionGroupMode>("date")
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set())

  const groups = useMemo(
    () => buildBacktestLabSessionGroups(trades, mode, strategyGroups),
    [trades, mode, strategyGroups]
  )

  const toggleGroup = (key: string) => {
    setExpandedKeys((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  if (!trades.length) {
    return (
      <p className="rounded-xl border border-white/10 bg-white/5 px-4 py-6 text-center text-sm text-gray-400">
        No trades to group in the current filter set.
      </p>
    )
  }

  return (
    <section className="mb-6 space-y-3">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-xl font-semibold text-white">Session organization</h2>
          <p className="text-sm text-gray-400">
            Group filtered backtests by date, strategy, or instrument — no separate
            session records.
          </p>
        </div>
        <CustomSelect
          value={mode}
          onChange={(value) => {
            setMode(value as BacktestLabSessionGroupMode)
            setExpandedKeys(new Set())
          }}
          {...BACKTEST_LAB_SELECT_PROPS}
          className="w-full sm:w-48"
          options={MODE_OPTIONS}
        />
      </div>

      <div className="space-y-2">
        {groups.map((group) => (
          <SessionGroupPanel
            key={group.key}
            group={group}
            expanded={expandedKeys.has(group.key)}
            onToggle={() => toggleGroup(group.key)}
          >
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              {group.trades.map((trade) => (
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
            </div>
          </SessionGroupPanel>
        ))}
      </div>
    </section>
  )
}
