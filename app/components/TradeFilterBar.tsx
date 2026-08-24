"use client"

import { useEffect, useState, type ReactNode } from "react"
import { useRouter } from "next/navigation"
import { DASHBOARD_MOBILE_TIMEFRAME_BTN_CLASS } from "@/app/components/dashboard/dashboardHeaderMobileUi"
import { DASHBOARD_MOBILE_FILTER_SHELL_CLASS } from "@/app/components/dashboard/dashboardMobileUi"
import DashboardTimeframePicker, {
  syncTimeframeDisplayLabel,
} from "@/app/components/dashboard/DashboardTimeframePicker"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_FILTER_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import { DASHBOARD_ALL_TIMEFRAME_LABEL } from "@/lib/dashboardTimeframeLabels"

/** Shared with account pickers — same destination as the filter bar action. */
export const MANAGE_ACCOUNTS_SETTINGS_HREF = "/settings#trading-accounts" as const
export const MANAGE_ACCOUNTS_VALUE = "__manage_accounts__"

const MODE_OPTIONS = [
  { label: "All Modes", value: "all" },
  { label: "Live", value: "live" },
  { label: "Funded", value: "funded" },
  { label: "Eval", value: "eval" },
] as const

export function navigateToManageAccounts(
  router: ReturnType<typeof useRouter>
) {
  router.push(MANAGE_ACCOUNTS_SETTINGS_HREF)
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
  /**
   * When true with `leading`, pins leading on the left at md+ without shifting
   * centered controls — used for dashboard Plan badge (desktop/tablet only).
   */
  leadingOverlay?: boolean
  /** Rendered immediately before the account selector (dashboard Add Trade, desktop). */
  beforeAccountSelect?: ReactNode
  /** Rendered to the right of the account selector on mobile (dashboard "+" action). */
  accountSelectAccessory?: ReactNode
  /** Appended controls (e.g. Show Advanced, Public Trades, settings) */
  trailing?: ReactNode
  /** PRO copy trading groups for unified account picker */
  isPro?: boolean
  copyGroups?: CopyTradingGroup[]
  /** Called when the account picker menu opens (lazy-load copy groups). */
  onAccountPickerOpen?: () => void
  /** Shown beside “All Modes” on small screens only */
  settingsNextToModes?: ReactNode
  /** Optional compact control shown beside “All Modes” on mobile */
  publicNextToModes?: ReactNode
  /**
   * Optional control immediately left of the Timeframe button on mobile
   * three-row layout (native Dashboard Trades shortcut). Hidden on md+.
   */
  beforeTimeframe?: ReactNode
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
  leadingOverlay = false,
  beforeAccountSelect,
  accountSelectAccessory,
  trailing,
  settingsNextToModes,
  publicNextToModes,
  beforeTimeframe,
  className = "",
  variant: _variant,
  mobileThreeRowLayout = false,
  fullWidth = false,
  isPro = false,
  copyGroups = [],
  onAccountPickerOpen,
}: TradeFilterBarProps) {
  const isTradesVariant = _variant === "trades"
  const [timeframeOpen, setTimeframeOpen] = useState(false)
  const [selectedTimeframe, setSelectedTimeframe] = useState(
    DASHBOARD_ALL_TIMEFRAME_LABEL
  )

  useEffect(() => {
    setSelectedTimeframe(syncTimeframeDisplayLabel(timeframe, selectedDate))
  }, [timeframe, selectedDate])

  const timeframeButtonLabel =
    selectedTimeframe === DASHBOARD_ALL_TIMEFRAME_LABEL
      ? "Timeframe"
      : selectedTimeframe

  function renderAccountSelect(className = "") {
    return (
      <TradeAccountPicker
        className={className}
        accounts={[]}
        isPro={isPro}
        copyGroups={copyGroups}
        filterValue={accountFilter}
        filterOptions={accounts}
        onFilterChange={onAccountChange}
        filterPlaceholder="All Accounts"
        showExternalCreateButton={false}
        hideManageAccounts={false}
        onPickerOpen={onAccountPickerOpen}
      />
    )
  }

  function renderLeading() {
    if (!leading) return null
    if (!leadingOverlay) return leading

    return (
      <div className="pointer-events-none absolute inset-y-0 left-3 z-10 hidden items-center md:flex md:left-4">
        <div className="pointer-events-auto">{leading}</div>
      </div>
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
            <div className="flex justify-center md:justify-start">{renderLeading()}</div>

            {accountSelectAccessory ? (
              <div className="flex w-full min-w-0 items-center gap-2 md:w-auto">
                <div className="min-w-0 flex-1 md:flex-none">
                  {renderAccountSelect()}
                </div>
                <div className="shrink-0 md:hidden">{accountSelectAccessory}</div>
              </div>
            ) : (
              <div className="w-full md:w-auto">
                {renderAccountSelect()}
              </div>
            )}

            <div className="flex w-full gap-2 md:w-auto md:items-center">
              <div className="flex-1 md:flex-none">
                <CustomSelect
                  value={accountTypeFilter}
                  onChange={onAccountTypeChange}
                  className="md:w-auto"
                  triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
                  options={[...MODE_OPTIONS]}
                />
              </div>
              <div className="flex-1 md:flex-none">
                <button
                  type="button"
                  onClick={() => setTimeframeOpen(true)}
                  className="w-full rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/20 md:h-[34px] md:w-auto md:py-0"
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
                ? `relative z-50 flex w-full max-w-full flex-col items-stretch gap-2 overflow-visible rounded-xl border border-white/10 bg-white/5 px-3 py-2 backdrop-blur-md ${DASHBOARD_MOBILE_FILTER_SHELL_CLASS} md:flex-row md:flex-wrap md:items-center md:justify-center md:gap-3 md:px-4 md:py-3 lg:flex-nowrap`
                : `relative z-50 flex max-w-full overflow-visible rounded-xl border border-white/10 bg-white/5 px-3 py-2 backdrop-blur-md md:gap-3 md:px-4 md:py-3 flex-wrap items-center justify-center gap-2 lg:flex-nowrap`
            }
          >
            {renderLeading()}

            {beforeAccountSelect ? (
              <div className="hidden md:contents">{beforeAccountSelect}</div>
            ) : null}

            {accountSelectAccessory ? (
              <div className="flex w-full min-w-0 items-center gap-2 md:contents">
                <div className="min-w-0 flex-1 md:contents">
                  {renderAccountSelect()}
                </div>
                <div className="shrink-0 md:hidden">{accountSelectAccessory}</div>
              </div>
            ) : (
              renderAccountSelect()
            )}

            {settingsNextToModes || publicNextToModes ? (
              <div
                className={`flex w-full min-w-0 items-stretch gap-2 md:block md:w-auto ${
                  mobileThreeRowLayout ? "justify-stretch" : "justify-center"
                }`}
              >
                <div
                  className={`min-w-0 md:w-auto md:flex-none ${
                    mobileThreeRowLayout ? "flex-1" : "flex-[1.5]"
                  }`}
                >
                  <CustomSelect
                    value={accountTypeFilter}
                    onChange={onAccountTypeChange}
                    className="md:w-auto"
                    triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
                    options={[...MODE_OPTIONS]}
                  />
                </div>
                {publicNextToModes ? (
                  <div
                    className={`flex min-w-0 items-stretch justify-center md:hidden ${
                      mobileThreeRowLayout ? "flex-1" : "shrink-0"
                    }`}
                  >
                    {publicNextToModes}
                  </div>
                ) : null}
                {settingsNextToModes ? (
                  <div
                    className={`flex items-stretch justify-center md:hidden ${
                      mobileThreeRowLayout ? "shrink-0" : "shrink-0"
                    }`}
                  >
                    {settingsNextToModes}
                  </div>
                ) : null}
              </div>
            ) : (
              <CustomSelect
                value={accountTypeFilter}
                onChange={onAccountTypeChange}
                className="w-auto shrink-0"
                triggerClassName={SELECT_FILTER_TRIGGER_CLASS}
                options={[...MODE_OPTIONS]}
              />
            )}

            {mobileThreeRowLayout ? (
              <div className="flex w-full items-stretch gap-2 md:contents">
                {beforeTimeframe ? (
                  <div className="flex shrink-0 items-stretch md:hidden">
                    {beforeTimeframe}
                  </div>
                ) : null}
                <div className="min-w-0 flex-1 md:w-auto md:flex-none">
                  <button
                    type="button"
                    onClick={() => setTimeframeOpen(true)}
                    className={`${DASHBOARD_MOBILE_TIMEFRAME_BTN_CLASS} md:w-auto md:rounded-lg md:px-4`}
                  >
                    {timeframeButtonLabel}
                  </button>
                </div>
                <div className="flex min-w-0 flex-1 items-stretch gap-2 md:contents">
                  {trailing}
                </div>
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

      <DashboardTimeframePicker
        open={timeframeOpen}
        onClose={() => setTimeframeOpen(false)}
        presentation="modal"
        timeframe={timeframe}
        onTimeframeChange={onTimeframeChange}
        selectedDate={selectedDate}
        onSelectedDateChange={onSelectedDateChange}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCustomRangeApply={onCustomRangeApply}
      />
    </>
  )
}
