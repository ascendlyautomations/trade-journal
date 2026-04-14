"use client"

import type { ReactNode } from "react"

const TIME_OPTIONS = [
  { label: "All", value: "all" },
  { label: "Daily", value: "daily" },
  { label: "Weekly", value: "weekly" },
  { label: "Monthly", value: "monthly" },
] as const

export type TradeFilterBarProps = {
  accounts: Array<{
    value: string
    label: string
    accountType?: string | null
  }>
  accountFilter: string
  onAccountChange: (value: string) => void
  accountTypeFilter: string
  onAccountTypeChange: (value: string) => void
  timeframe: string
  onTimeframeChange: (value: string) => void
  selectedDate: string
  onSelectedDateChange: (value: string) => void
  /** Prepended controls (e.g. Trade History win/loss toggle) */
  leading?: ReactNode
  /** Appended controls (e.g. Show Advanced, Public Trades, settings) */
  trailing?: ReactNode
  /** Outer wrapper, e.g. mb-5 w-full */
  className?: string
}

export default function TradeFilterBar({
  accounts,
  accountFilter,
  onAccountChange,
  accountTypeFilter,
  onAccountTypeChange,
  timeframe,
  onTimeframeChange,
  selectedDate,
  onSelectedDateChange,
  leading,
  trailing,
  className = "",
}: TradeFilterBarProps) {
  return (
    <div className={`flex w-full justify-center ${className}`}>
      <div className="relative z-50 flex max-w-full flex-wrap items-center justify-center gap-3 overflow-visible rounded-xl border border-white/10 bg-white/5 px-4 py-3 backdrop-blur-md lg:flex-nowrap">
        {leading}

        <select
          value={accountFilter}
          onChange={(e) => onAccountChange(e.target.value)}
          className="shrink-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="all">All Accounts</option>
          {accounts.map((acc) => (
            <option key={acc.value} value={acc.value}>
              {acc.label}
            </option>
          ))}
        </select>

        <select
          value={accountTypeFilter}
          onChange={(e) => onAccountTypeChange(e.target.value)}
          className="shrink-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="all">All Modes</option>
          <option value="funded">Funded</option>
          <option value="eval">Eval</option>
          <option value="live">Live</option>
        </select>

        <div className="flex shrink-0 gap-2">
          {TIME_OPTIONS.map(({ label, value }) => (
            <button
              key={value}
              type="button"
              onClick={() => onTimeframeChange(value)}
              className={`shrink-0 whitespace-nowrap rounded-md px-3 py-1 text-sm ${
                timeframe === value
                  ? "bg-emerald-500 text-white hover:bg-emerald-600"
                  : "bg-white/10 text-white hover:bg-white/20"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <div className="relative z-50 shrink-0">
          <input
            type="date"
            value={selectedDate}
            onChange={(e) => onSelectedDateChange(e.target.value)}
            className="rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 pr-10 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-500 [color-scheme:dark]"
            style={{ colorScheme: "dark" }}
          />

          {selectedDate ? (
            <button
              type="button"
              onClick={() => onSelectedDateChange("")}
              className="absolute right-1 top-1/2 -translate-y-1/2 rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20"
              aria-label="Clear date"
            >
              <span className="text-base leading-none" aria-hidden>
                🗑
              </span>
            </button>
          ) : null}
        </div>

        {trailing}
      </div>
    </div>
  )
}
