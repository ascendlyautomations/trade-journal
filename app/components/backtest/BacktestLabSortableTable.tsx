"use client"

import type { BacktestLabGroupStats, BacktestLabSortDirection, BacktestLabSortKey } from "@/lib/backtestLabAnalytics"
import type { BacktestLabTableColumn } from "./backtestLabTableFormat"

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
      <p className="rounded-xl border border-white/10 bg-white/5 px-4 py-6 text-center text-sm text-gray-400">
        {emptyMessage}
      </p>
    )
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-white/10 bg-white/5 backdrop-blur-md">
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
  )
}
