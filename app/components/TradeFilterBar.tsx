"use client"

import { useEffect, useState, type ReactNode } from "react"
import { useRouter } from "next/navigation"

const MANAGE_ACCOUNTS_VALUE = "__manage_accounts__"

/** Shared with account pickers — same destination as the filter bar action. */
export const MANAGE_ACCOUNTS_SETTINGS_HREF = "/settings#trading-accounts" as const
export { MANAGE_ACCOUNTS_VALUE }

export function navigateToManageAccounts(
  router: ReturnType<typeof useRouter>
) {
  router.push(MANAGE_ACCOUNTS_SETTINGS_HREF)
}

const TF_LABEL_FROM_VALUE: Record<string, string> = {
  all: "All",
  daily: "Daily",
  weekly: "Weekly",
  monthly: "Monthly",
  yearly: "Yearly",
  custom: "Custom",
}

const PRESET_LABEL_TO_VALUE: Record<string, string> = {
  All: "all",
  Daily: "daily",
  Weekly: "weekly",
  Monthly: "monthly",
  Yearly: "yearly",
}

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
  /** Custom range (YYYY-MM-DD), used when timeframe is `custom` */
  customRangeStart?: string
  customRangeEnd?: string
  onCustomRangeApply?: (start: string, end: string) => void
  /** Prepended controls (e.g. Trade History win/loss toggle) */
  leading?: ReactNode
  /** Appended controls (e.g. Show Advanced, Public Trades, settings) */
  trailing?: ReactNode
  /** Shown beside “All Modes” on small screens only */
  settingsNextToModes?: ReactNode
  /** Optional compact control shown beside “All Modes” on mobile */
  publicNextToModes?: ReactNode
  /** Outer wrapper, e.g. mb-5 w-full */
  className?: string
  /** Unused layout hint for pages that differentiate usage */
  variant?: string
  /** Dashboard-only mobile three-row layout; desktop remains unchanged */
  mobileThreeRowLayout?: boolean
  /** Trades page: full-width row, no centered shrink-wrap */
  fullWidth?: boolean
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
  customRangeStart = "",
  customRangeEnd = "",
  onCustomRangeApply,
  leading,
  trailing,
  settingsNextToModes,
  publicNextToModes,
  className = "",
  variant: _variant,
  mobileThreeRowLayout = false,
  fullWidth = false,
}: TradeFilterBarProps) {
  const router = useRouter()
  const isTradesVariant = _variant === "trades"
  const [timeframeOpen, setTimeframeOpen] = useState(false)
  const [selectedTimeframe, setSelectedTimeframe] = useState("All")
  const [startDate, setStartDate] = useState("")
  const [endDate, setEndDate] = useState("")

  useEffect(() => {
    if (timeframe === "custom") {
      setSelectedTimeframe("Custom")
    } else if (selectedDate?.trim()) {
      setSelectedTimeframe("Specific Date")
    } else {
      setSelectedTimeframe(TF_LABEL_FROM_VALUE[timeframe] ?? "All")
    }
  }, [timeframe, selectedDate])

  useEffect(() => {
    if (!timeframeOpen) return
    if (timeframe === "custom") {
      setStartDate(customRangeStart)
      setEndDate(customRangeEnd)
    } else if (selectedDate?.trim()) {
      setStartDate(selectedDate)
      setEndDate(selectedDate)
    } else {
      setStartDate("")
      setEndDate("")
    }
  }, [timeframeOpen, timeframe, selectedDate, customRangeStart, customRangeEnd])

  const timeframeButtonLabel =
    selectedTimeframe === "All" ? "Timeframe" : selectedTimeframe

  function openNativeDatePicker(input: HTMLInputElement) {
    try {
      input.showPicker()
    } catch {
      input.focus()
    }
  }

  function handleAccountFilterChange(value: string) {
    if (value === MANAGE_ACCOUNTS_VALUE) {
      navigateToManageAccounts(router)
      return
    }
    onAccountChange(value)
  }

  const accountSelectClassName =
    "h-[34px] min-w-0 rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0"

  function renderAccountSelect(className: string) {
    return (
      <select
        value={accountFilter}
        onChange={(e) => handleAccountFilterChange(e.target.value)}
        className={className}
      >
        <option value="all">All Accounts</option>
        {accounts.map((acc) => (
          <option key={acc.value} value={acc.value}>
            {acc.label}
          </option>
        ))}
        <option disabled>────────────────────</option>
        <option value={MANAGE_ACCOUNTS_VALUE}>⚙️ Manage Accounts</option>
      </select>
    )
  }

  return (
    <>
      <div
        className={
          fullWidth
            ? `w-full flex flex-wrap items-center justify-center gap-3 ${className}`
            : `flex w-full justify-center ${className}`
        }
      >
        {fullWidth ? (
          <div
            className={`relative z-50 flex max-w-full overflow-visible rounded-xl border border-white/10 bg-white/5 backdrop-blur-md w-full flex-col gap-3 md:flex-row md:flex-wrap md:items-center md:justify-center md:px-4 md:py-3 ${
              isTradesVariant ? "px-2 py-3" : "px-3 py-2"
            }`}
          >
            <div className="flex justify-center md:justify-start">{leading}</div>

            <div className="w-full md:w-auto">
              {renderAccountSelect(`${accountSelectClassName} w-full`)}
            </div>

            <div className="flex w-full gap-2 md:w-auto md:items-center">
              <div className="flex-1 md:flex-none">
                <select
                  value={accountTypeFilter}
                  onChange={(e) => onAccountTypeChange(e.target.value)}
                  className="h-[34px] w-full min-w-0 rounded-md border border-white/10 bg-[#0f172a] px-2 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0 md:px-3"
                >
                  <option value="all">All Modes</option>
                  <option value="live">Live</option>
                  <option value="funded">Funded</option>
                  <option value="eval">Eval</option>
                </select>
              </div>
              <div className="flex-1 md:flex-none">
                <button
                  type="button"
                  onClick={() => setTimeframeOpen(true)}
                  className="w-full rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/20 md:w-auto"
                >
                  {timeframeButtonLabel}
                </button>
              </div>
            </div>

            <div className="flex w-full gap-2 justify-between md:w-auto md:justify-center">
              {trailing}
            </div>
          </div>
        ) : (
          <div
            className={
              mobileThreeRowLayout
                ? `relative z-50 flex max-w-full overflow-visible rounded-xl border border-white/10 bg-white/5 px-3 py-2 backdrop-blur-md md:gap-3 md:px-4 md:py-3 w-full flex-col items-stretch gap-2 md:flex-row md:flex-wrap md:items-center md:justify-center lg:flex-nowrap`
                : `relative z-50 flex max-w-full overflow-visible rounded-xl border border-white/10 bg-white/5 px-3 py-2 backdrop-blur-md md:gap-3 md:px-4 md:py-3 flex-wrap items-center justify-center gap-2 lg:flex-nowrap`
            }
          >
            {leading}

            {renderAccountSelect(`${accountSelectClassName} w-full`)}

            {settingsNextToModes || publicNextToModes ? (
              <div
                className={`flex w-full min-w-0 items-center gap-2 md:block md:w-auto ${
                  mobileThreeRowLayout ? "justify-stretch" : "justify-center"
                }`}
              >
                <div
                  className={`min-w-0 md:w-auto md:flex-none ${
                    mobileThreeRowLayout ? "flex-1" : "flex-[1.5]"
                  }`}
                >
                  <select
                    value={accountTypeFilter}
                    onChange={(e) => onAccountTypeChange(e.target.value)}
                    className="h-[34px] w-full min-w-0 rounded-md border border-white/10 bg-[#0f172a] px-2 py-1 text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0 md:px-3"
                  >
                    <option value="all">All Modes</option>
                    <option value="live">Live</option>
                    <option value="funded">Funded</option>
                    <option value="eval">Eval</option>
                  </select>
                </div>
                {publicNextToModes ? (
                  <div
                    className={`flex items-center justify-center md:hidden ${
                      mobileThreeRowLayout ? "flex-1" : "shrink-0"
                    }`}
                  >
                    {publicNextToModes}
                  </div>
                ) : null}
                {settingsNextToModes ? (
                  <div
                    className={`flex items-center justify-center md:hidden ${
                      mobileThreeRowLayout ? "hidden" : "shrink-0"
                    }`}
                  >
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
                <option value="live">Live</option>
                <option value="funded">Funded</option>
                <option value="eval">Eval</option>
              </select>
            )}

            {mobileThreeRowLayout ? (
              <div className="flex w-full items-center gap-2 md:contents">
                <div className="flex-1 md:w-auto md:flex-none">
                  <button
                    type="button"
                    onClick={() => setTimeframeOpen(true)}
                    className="w-full rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/20 md:w-auto"
                  >
                    {timeframeButtonLabel}
                  </button>
                </div>
                <div className="flex-1 md:contents">{trailing}</div>
                {settingsNextToModes ? (
                  <div className="flex h-[34px] w-12 items-center justify-center md:hidden">
                    {settingsNextToModes}
                  </div>
                ) : null}
              </div>
            ) : (
              <>
                <div className="flex w-full shrink-0 justify-center md:w-auto">
                  <button
                    type="button"
                    onClick={() => setTimeframeOpen(true)}
                    className="px-4 py-2 rounded-lg bg-white/10 hover:bg-white/20 text-white text-sm font-medium transition"
                  >
                    {timeframeButtonLabel}
                  </button>
                </div>

                {trailing}
              </>
            )}
          </div>
        )}
      </div>

      {timeframeOpen ? (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="w-full max-w-md bg-[#0b1f3a] rounded-2xl p-6 border border-white/10 shadow-xl">
            <h2 className="text-lg font-semibold text-white mb-4">
              Select Timeframe
            </h2>

            <div className="grid grid-cols-2 gap-3 mb-4">
              {(["All", "Daily", "Weekly", "Monthly", "Yearly"] as const).map(
                (tf) => (
                  <button
                    key={tf}
                    type="button"
                    onClick={() => {
                      const v = PRESET_LABEL_TO_VALUE[tf]
                      setSelectedTimeframe(tf)
                      onSelectedDateChange("")
                      onTimeframeChange(v)
                      setTimeframeOpen(false)
                    }}
                    className="px-3 py-2 rounded-lg bg-white/10 hover:bg-green-500/20 text-white text-sm"
                  >
                    {tf}
                  </button>
                )
              )}
            </div>

            <div className="mt-5">
              <p className="text-sm text-white/60 mb-2">Specific Date</p>

              <input
                type="date"
                value={startDate}
                onFocus={(e) => openNativeDatePicker(e.currentTarget)}
                onChange={(e) => {
                  const v = e.target.value
                  setStartDate(v)
                  setEndDate(v)
                }}
                className="tt-timeframe-date h-11 w-full min-w-0 cursor-pointer rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 py-2 text-sm text-white shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus:border-emerald-400/60 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 [color-scheme:dark]"
              />

              <button
                type="button"
                onClick={() => {
                  if (!startDate?.trim()) return
                  onSelectedDateChange(startDate)
                  setEndDate(startDate)
                  onTimeframeChange("all")
                  setSelectedTimeframe("Specific Date")
                  setTimeframeOpen(false)
                }}
                className="w-full mt-2 py-2 rounded-lg bg-green-500 text-black font-medium"
              >
                Apply Specific Date
              </button>
            </div>

            <div className="mt-5">
              <p className="text-sm text-white/60 mb-2">Custom Range</p>

              <div className="flex items-center gap-2 overflow-hidden">
                <input
                  type="date"
                  value={startDate}
                  onFocus={(e) => openNativeDatePicker(e.currentTarget)}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="tt-timeframe-date h-11 w-full min-w-0 cursor-pointer rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 py-2 text-sm text-white shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus:border-emerald-400/60 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 [color-scheme:dark]"
                />
                <input
                  type="date"
                  value={endDate}
                  onFocus={(e) => openNativeDatePicker(e.currentTarget)}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="tt-timeframe-date h-11 w-full min-w-0 cursor-pointer rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 py-2 text-sm text-white shadow-inner shadow-black/20 transition hover:border-blue-300/40 focus:border-emerald-400/60 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 [color-scheme:dark]"
                />
              </div>

              <button
                type="button"
                onClick={() => {
                  if (!startDate?.trim() || !endDate?.trim()) return
                  onSelectedDateChange("")
                  onCustomRangeApply?.(startDate, endDate)
                  setSelectedTimeframe("Custom")
                  setTimeframeOpen(false)
                }}
                className="w-full mt-2 py-2 rounded-lg bg-green-500 text-black font-medium"
              >
                Apply Range
              </button>
            </div>

            <button
              type="button"
              onClick={() => {
                setStartDate("")
                setEndDate("")
                onSelectedDateChange("")
                onTimeframeChange("all")
                setSelectedTimeframe("All")
                setTimeframeOpen(false)
              }}
              className="w-full mt-4 py-2 rounded-lg bg-white/10 hover:bg-white/20 text-white text-sm"
            >
              Clear Dates
            </button>

            <button
              type="button"
              onClick={() => setTimeframeOpen(false)}
              className="mt-4 text-sm text-white/50 hover:text-white"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}
    </>
  )
}
