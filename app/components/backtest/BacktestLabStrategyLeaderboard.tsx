"use client"

import { useMemo, useState } from "react"
import {
  sortBacktestLabGroupStats,
  type BacktestLabGroupStats,
  type BacktestLabSortDirection,
  type BacktestLabSortKey,
} from "@/lib/backtestLabAnalytics"
import BacktestLabSortableTable from "./BacktestLabSortableTable"
import {
  formatBacktestLabAvgR,
  formatBacktestLabAvgWinLoss,
  formatBacktestLabExpectancy,
  formatBacktestLabNetPnl,
  formatBacktestLabProfitFactor,
  formatBacktestLabWinRate,
  pnlToneClass,
  type BacktestLabTableColumn,
} from "./backtestLabTableFormat"

export type BacktestLabStrategyLeaderboardProps = {
  rows: BacktestLabGroupStats[]
  selectedStrategyKey: string | null
  onSelectStrategy: (key: string) => void
}

const STRATEGY_COLUMNS: BacktestLabTableColumn[] = [
  {
    id: "label",
    label: "Strategy",
    cell: (row) => row.label,
    cellClass: () => "font-medium text-white",
  },
  {
    id: "totalTrades",
    label: "Trades",
    align: "right",
    cell: (row) => String(row.totalTrades),
  },
  {
    id: "winRate",
    label: "Win rate",
    align: "right",
    cell: (row) => formatBacktestLabWinRate(row.winRate),
  },
  {
    id: "netPnl",
    label: "Net P&L",
    align: "right",
    cell: (row) => formatBacktestLabNetPnl(row.netPnl),
    cellClass: (row) => pnlToneClass(row.netPnl),
  },
  {
    id: "profitFactor",
    label: "Profit factor",
    align: "right",
    cell: (row) => formatBacktestLabProfitFactor(row),
  },
  {
    id: "expectancy",
    label: "Expectancy",
    align: "right",
    cell: (row) => formatBacktestLabExpectancy(row.expectancy),
    cellClass: (row) =>
      row.expectancy != null ? pnlToneClass(row.expectancy) : undefined,
  },
  {
    id: "avgRR",
    label: "Avg R",
    align: "right",
    cell: (row) => formatBacktestLabAvgR(row.avgRR),
  },
  {
    id: "avgWin",
    label: "Avg win",
    align: "right",
    cell: (row) => formatBacktestLabAvgWinLoss(row.avgWin),
    cellClass: () => "text-emerald-400/90",
  },
  {
    id: "avgLoss",
    label: "Avg loss",
    align: "right",
    cell: (row) => formatBacktestLabAvgWinLoss(row.avgLoss),
    cellClass: () => "text-red-400/90",
  },
]

export default function BacktestLabStrategyLeaderboard({
  rows,
  selectedStrategyKey,
  onSelectStrategy,
}: BacktestLabStrategyLeaderboardProps) {
  const [sortKey, setSortKey] = useState<BacktestLabSortKey>("netPnl")
  const [sortDirection, setSortDirection] =
    useState<BacktestLabSortDirection>("desc")

  const sorted = useMemo(
    () => sortBacktestLabGroupStats(rows, sortKey, sortDirection),
    [rows, sortKey, sortDirection]
  )

  const handleSort = (key: BacktestLabSortKey) => {
    if (key === sortKey) {
      setSortDirection((d) => (d === "asc" ? "desc" : "asc"))
    } else {
      setSortKey(key)
      setSortDirection(key === "label" ? "asc" : "desc")
    }
  }

  return (
    <section className="mb-6 space-y-2">
      <div>
        <h2 className="text-xl font-semibold text-white">Strategy leaderboard</h2>
        <p className="text-sm text-gray-400">
          Grouped by strategy name (case-insensitive). Click a row to filter trades.
        </p>
      </div>
      <BacktestLabSortableTable
        rows={sorted}
        columns={STRATEGY_COLUMNS}
        sortKey={sortKey}
        sortDirection={sortDirection}
        onSort={handleSort}
        emptyMessage="No backtest trades in the current account, date, and instrument filters."
        getRowKey={(row) => row.key}
        onRowClick={(row) => onSelectStrategy(row.key)}
        selectedRowKey={selectedStrategyKey}
        ariaLabel="Strategy performance leaderboard"
      />
    </section>
  )
}
