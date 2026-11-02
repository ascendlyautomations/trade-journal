"use client"

import type { BacktestLabGroupStats, BacktestLabSortDirection, BacktestLabSortKey } from "@/lib/backtestLabAnalytics"
import {
  formatBacktestLabAvgR,
  formatBacktestLabNetPnl,
  formatBacktestLabWinRate,
  pnlToneClass,
  type BacktestLabTableColumn,
} from "./backtestLabTableFormat"

type BacktestLabSortableTableProps = {
  rows: BacktestLabGroupStats[]
  columns: BacktestLabTableColumn[]
  sortKey: BacktestLabSortKey
  sortDirection: BacktestLabSortDirection
  onSort: (key: BacktestLabSortKey) => void
  emptyMessage: string
  getRowKey: (row: BacktestLabGroupStats) => string
  onRowClick?: (row: BacktestLabGroupStats) => void
  selectedRowKey?: string | null
  ariaLabel: string
}

function SortIndicator({
  active,
  direction,
}: {
  active: boolean
  direction: BacktestLabSortDirection
}) {
  if (!active) return <span className="text-gray-600">↕</span>
  return <span className="text-blue-300">{direction === "asc" ? "↑" : "↓"}</span>
}

export default function BacktestLabSortableTable({
  rows,
  columns,
  sortKey,
  sortDirection,
  onSort,
  emptyMessage,
  getRowKey,
  onRowClick,
  selectedRowKey,
  ariaLabel,
}: BacktestLabSortableTableProps) {
  if (!rows.length) {
    return (
      <p className="rounded-xl border border-white/10 bg-white/5 px-4 py-6 text-center text-sm text-gray-400 max-md:px-3 max-md:py-5">
        {emptyMessage}
      </p>
    )
  }

  return (
    <>
    <div className="grid grid-cols-2 gap-2 md:hidden">
      {rows.map((row) => {
        const key = getRowKey(row)
        const selected = selectedRowKey != null && selectedRowKey === key
        const cardClass = `rounded-[14px] border bg-white/5 p-3 text-left ${
          selected ? "border-blue-400/40 bg-blue-500/10" : "border-white/10"
        }`
        const body = (
          <>
            <p className="truncate text-[13px] font-semibold text-white">
              {row.label}
            </p>
            <p className="mt-1 text-[11px] text-gray-400">
              Trades: {row.totalTrades}
            </p>
            <p className="text-[11px] text-gray-400">
              Win rate: {formatBacktestLabWinRate(row.winRate)}
            </p>
            <p className={`text-[11px] font-medium ${pnlToneClass(row.netPnl)}`}>
              PnL: {formatBacktestLabNetPnl(row.netPnl)}
            </p>
            <p className="text-[11px] text-gray-500">
              Avg RR: {formatBacktestLabAvgR(row.avgRR)}
            </p>
          </>
        )
        return onRowClick ? (
          <button
            key={key}
            type="button"
            onClick={() => onRowClick(row)}
            className={cardClass}
          >
            {body}
          </button>
        ) : (
          <div key={key} className={cardClass}>
            {body}
          </div>
        )
      })}
    </div>
    <div className="hidden overflow-x-auto rounded-xl border border-white/10 bg-white/5 backdrop-blur-md md:block">
      <table className="w-full min-w-[640px] text-left text-sm" aria-label={ariaLabel}>
        <thead>
          <tr className="border-b border-white/10 text-xs uppercase tracking-wide text-gray-400">
            {columns.map((column) => {
              const sortable = column.id !== "actions"
              const isLabel = column.id === "label"
              const headerSortKey = isLabel ? "label" : (column.id as BacktestLabSortKey)
              return (
                <th
                  key={column.id}
                  className={`px-3 py-2.5 font-medium ${
                    column.align === "right" ? "text-right" : "text-left"
                  }`}
                >
                  {sortable ? (
                    <button
                      type="button"
                      onClick={() => onSort(headerSortKey)}
                      className="inline-flex items-center gap-1 hover:text-white"
                    >
                      {column.label}
                      <SortIndicator
                        active={sortKey === headerSortKey}
                        direction={sortDirection}
                      />
                    </button>
                  ) : (
                    column.label
                  )}
                </th>
              )
            })}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const key = getRowKey(row)
            const selected = selectedRowKey != null && selectedRowKey === key
            return (
              <tr
                key={key}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                className={`border-b border-white/5 last:border-0 ${
                  onRowClick ? "cursor-pointer hover:bg-white/5" : ""
                } ${selected ? "bg-blue-500/10" : ""}`}
              >
                {columns.map((column) => (
                  <td
                    key={column.id}
                    className={`px-3 py-2.5 tabular-nums text-gray-200 ${
                      column.align === "right" ? "text-right" : "text-left"
                    } ${column.cellClass?.(row) ?? ""}`}
                  >
                    {column.cell(row)}
                  </td>
                ))}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
    </>
  )
}
