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
  /** Shown beside “All Modes” on small screens only (hide desktop copy with `hidden md:flex` on the trailing instance) */
  settingsNextToModes?: ReactNode
  /** Optional compact public-trades control shown beside “All Modes” on mobile */
  publicNextToModes?: ReactNode
  /** Optional mobile date control rendered beside “All Modes” */
  dateNextToModes?: ReactNode
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
  settingsNextToModes,
  publicNextToModes,
  dateNextToModes,
  className = "",
}: TradeFilterBarProps) {
  return (
    <div className={`flex w-full justify-center ${className}`}>
      <div className="relative z-50 flex max-w-full flex-wrap items-center justify-center gap-2 overflow-visible rounded-xl border border-white/10 bg-white/5 px-3 py-2 backdrop-blur-md md:gap-3 md:px-4 md:py-3 lg:flex-nowrap">
        {leading}

        <select
          value={accountFilter}
          onChange={(e) => onAccountChange(e.target.value)}
          className="h-[34px] w-full min-w-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0"
        >
          <option value="all">All Accounts</option>
          {accounts.map((acc) => (
            <option key={acc.value} value={acc.value}>
              {acc.label}
            </option>
          ))}
        </select>

        {settingsNextToModes || dateNextToModes || publicNextToModes ? (
          <div className="flex w-full min-w-0 items-center justify-center gap-1.5 md:block md:w-auto">
            <div className="min-w-0 flex-[1.5] md:w-auto md:flex-none">
              <select
                value={accountTypeFilter}
                onChange={(e) => onAccountTypeChange(e.target.value)}
                className="h-[34px] w-full min-w-0 rounded-md border border-white/10 bg-[#0f172a] px-2 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0 md:px-3"
              >
                <option value="all">All Modes</option>
                <option value="funded">Funded</option>
                <option value="eval">Eval</option>
                <option value="live">Live</option>
              </select>
            </div>
            {publicNextToModes ? (
              <div className="flex shrink-0 items-center justify-center md:hidden">
                {publicNextToModes}
              </div>
            ) : null}
            {dateNextToModes ? (
              <div className="flex shrink-0 items-center justify-center md:hidden">
                {dateNextToModes}
              </div>
            ) : null}
            {settingsNextToModes ? (
              <div className="flex shrink-0 items-center justify-center md:hidden">
                {settingsNextToModes}
              </div>
            ) : null}
          </div>
        ) : (
          <select
            value={accountTypeFilter}
            onChange={(e) => onAccountTypeChange(e.target.value)}
            className="h-[34px] shrink-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Modes</option>
            <option value="funded">Funded</option>
            <option value="eval">Eval</option>
            <option value="live">Live</option>
          </select>
        )}

        <div className="flex w-full shrink-0 justify-center gap-2 md:w-auto">
          {TIME_OPTIONS.map(({ label, value }) => (
            <button
              key={value}
              type="button"
              onClick={() => onTimeframeChange(value)}
              className={`flex h-[34px] shrink-0 items-center whitespace-nowrap rounded-md px-3 py-1 text-sm ${
                timeframe === value
                  ? "bg-emerald-500 text-white hover:bg-emerald-600"
                  : "bg-white/10 text-white hover:bg-white/20"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <div
          className={`relative z-10 shrink-0 ${
            dateNextToModes ? "hidden md:block" : ""
          }`}
        >
          <input
            type="date"
            value={selectedDate}
            onChange={(e) => onSelectedDateChange(e.target.value)}
            className="relative z-10 h-[34px] rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 pr-10 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-500 [color-scheme:dark]"
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
