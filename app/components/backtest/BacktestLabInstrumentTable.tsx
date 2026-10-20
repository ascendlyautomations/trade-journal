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
  formatBacktestLabNetPnl,
  formatBacktestLabProfitFactor,
  formatBacktestLabWinRate,
  pnlToneClass,
  type BacktestLabTableColumn,
} from "./backtestLabTableFormat"

export type BacktestLabInstrumentTableProps = {
  rows: BacktestLabGroupStats[]
}

const INSTRUMENT_COLUMNS: BacktestLabTableColumn[] = [
  {
    id: "label",
    label: "Instrument",
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
    id: "netPnl",
    label: "Net P&L",
    align: "right",
    cell: (row) => formatBacktestLabNetPnl(row.netPnl),
    cellClass: (row) => pnlToneClass(row.netPnl),
  },
  {
    id: "winRate",
    label: "Win rate",
    align: "right",
    cell: (row) => formatBacktestLabWinRate(row.winRate),
  },
  {
    id: "profitFactor",
    label: "Profit factor",
    align: "right",
    cell: (row) => formatBacktestLabProfitFactor(row),
  },
  {
    id: "avgRR",
    label: "Avg R",
    align: "right",
    cell: (row) => formatBacktestLabAvgR(row.avgRR),
  },
]

export default function BacktestLabInstrumentTable({
  rows,
}: BacktestLabInstrumentTableProps) {
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
        <h2 className="text-xl font-semibold text-white">Instrument performance</h2>
        <p className="text-sm text-gray-400">
          Futures symbols normalized (e.g. NQ vs MNQ stay separate).
        </p>
      </div>
      <BacktestLabSortableTable
        rows={sorted}
        columns={INSTRUMENT_COLUMNS}
        sortKey={sortKey}
        sortDirection={sortDirection}
        onSort={handleSort}
        emptyMessage="No instruments in the current filter set."
        getRowKey={(row) => row.key}
        ariaLabel="Instrument performance breakdown"
      />
    </section>
  )
}
