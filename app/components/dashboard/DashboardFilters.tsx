"use client"

import { useState, type Dispatch, type SetStateAction } from "react"
import Link from "next/link"
import TradeFilterBar, {
  type TradeFilterBarProps,
} from "@/app/components/TradeFilterBar"
import PerformanceShareButton from "@/app/components/PerformanceShareButton"
import DashboardGearSettings from "./DashboardGearSettings"
import {
  DASHBOARD_MOBILE_ACTION_BTN_CLASS,
  DASHBOARD_MOBILE_PUBLIC_BTN_BASE,
} from "./dashboardHeaderMobileUi"
import { DASHBOARD_MOBILE_FILTER_MARGIN_CLASS } from "./dashboardMobileUi"
import type { GearDraftState } from "./dashboardGearTypes"
import PlatformDashboardCalendarButton from "@/app/components/platform/PlatformDashboardCalendarButton"
import PlatformDashboardTradesButton from "@/app/components/platform/PlatformDashboardTradesButton"
import { usePlatformPresentation } from "@/app/components/platform/usePlatformPresentation"
import NativeIosDashboardActionBar from "@/app/components/platform/native/NativeIosDashboardActionBar"
import NativeIosDashboardFilterSheet from "@/app/components/platform/native/NativeIosDashboardFilterSheet"

export type DashboardFiltersProps = {
  isPro: boolean
  accounts: TradeFilterBarProps["accounts"]
  accountFilter: string
  onAccountChange: (value: string) => void
  accountTypeFilter: string
  onAccountTypeChange: (value: string) => void
  timeframe: string
  onTimeframeChange: (value: string) => void
  customRangeStart: string
  customRangeEnd: string
  onCustomRangeApply: (start: string, end: string) => void
  selectedDate: string
  onSelectedDateChange: (value: string) => void
  showPublicOnly: boolean
  onTogglePublicOnly: () => void
  onOpenPerformanceShare: () => void
  /** Opens the existing Quick Trade flow. */
  onOpenQuickInput: () => void
  /** Opens the trading report modal (mobile header row 3). */
  onOpenTradingReport?: () => void
  showTradingReportButton?: boolean
  showControls: boolean
  onToggleShowControls: () => void
  gearDraft: GearDraftState | null
  setGearDraft: Dispatch<SetStateAction<GearDraftState | null>>
  ddInputFocused: boolean
  setDdInputFocused: (focused: boolean) => void
  savingGearSettings: boolean
  hasUser: boolean
  onSaveGear: () => void
  onCancelGear: () => void
  /** PRO copy trading groups for unified account picker */
  copyGroups?: import("@/lib/copyTradingGroups").CopyTradingGroup[]
  /** Lazy-load copy trading groups when filter UI opens. */
  onRequestCopyGroups?: () => void
  /** When false, hides Public toggle and Share performance controls (zero-trade dashboard). */
  showShareControls?: boolean
  /** Subtle link when filters indicate prop firm context (account or Eval/Funded mode). */
  showPropFirmLink?: boolean
}

export default function DashboardFilters({
  isPro,
  accounts,
  accountFilter,
  onAccountChange,
  accountTypeFilter,
  onAccountTypeChange,
  timeframe,
  onTimeframeChange,
  customRangeStart,
  customRangeEnd,
  onCustomRangeApply,
  selectedDate,
  onSelectedDateChange,
  showPublicOnly,
  onTogglePublicOnly,
  onOpenPerformanceShare,
  onOpenQuickInput,
  onOpenTradingReport,
  showTradingReportButton = false,
  showControls,
  onToggleShowControls,
  gearDraft,
  setGearDraft,
  ddInputFocused,
  setDdInputFocused,
  savingGearSettings,
  hasUser,
  onSaveGear,
  onCancelGear,
  showShareControls = true,
  showPropFirmLink = false,
  copyGroups = [],
  onRequestCopyGroups,
}: DashboardFiltersProps) {
  const { isNativeIos } = usePlatformPresentation()
  const [filterSheetOpen, setFilterSheetOpen] = useState(false)

  if (isNativeIos) {
    /** Dismiss sheet and discard unsaved preference draft (not used after Save). */
    const dismissFilterSheet = () => {
      if (showControls) onCancelGear()
      setFilterSheetOpen(false)
    }

    return (
      <div>
        <div className="max-md:-mx-2 md:contents">
          <NativeIosDashboardActionBar
            accounts={accounts}
            accountFilter={accountFilter}
            onAccountChange={onAccountChange}
            isPro={isPro}
            copyGroups={copyGroups}
            onOpenQuickInput={onOpenQuickInput}
            onOpenFilters={() => {
              onRequestCopyGroups?.()
              setFilterSheetOpen(true)
            }}
            onAccountPickerOpen={onRequestCopyGroups}
          />
        </div>
        <div className={DASHBOARD_MOBILE_FILTER_MARGIN_CLASS}>
          <NativeIosDashboardFilterSheet
            open={filterSheetOpen}
            onClose={dismissFilterSheet}
            accountTypeFilter={accountTypeFilter}
            onAccountTypeChange={onAccountTypeChange}
            timeframe={timeframe}
            onTimeframeChange={onTimeframeChange}
            customRangeStart={customRangeStart}
            customRangeEnd={customRangeEnd}
            onCustomRangeApply={onCustomRangeApply}
            selectedDate={selectedDate}
            onSelectedDateChange={onSelectedDateChange}
            showPublicOnly={showPublicOnly}
            onTogglePublicOnly={onTogglePublicOnly}
            onOpenPerformanceShare={onOpenPerformanceShare}
            showShareControls={showShareControls}
            showTradingReportButton={showTradingReportButton}
            onOpenTradingReport={onOpenTradingReport}
            showControls={showControls}
            onToggleShowControls={onToggleShowControls}
            gearDraft={gearDraft}
            setGearDraft={setGearDraft}
            ddInputFocused={ddInputFocused}
            setDdInputFocused={setDdInputFocused}
            savingGearSettings={savingGearSettings}
            hasUser={hasUser}
            onSaveGear={() => {
              onSaveGear()
              setFilterSheetOpen(false)
            }}
            onCancelGear={() => {
              onCancelGear()
              setFilterSheetOpen(false)
            }}
          />
          {showPropFirmLink ? (
            <div className="mt-2 mb-1 flex justify-end">
              <Link
                href="/analytics/propfirm"
                className="text-xs text-blue-300 transition hover:text-blue-200"
              >
                View Prop Firm Dashboard →
              </Link>
            </div>
          ) : null}
        </div>
      </div>
    )
  }

  const gearSettings = (
    <DashboardGearSettings
      showControls={showControls}
      onToggleShowControls={onToggleShowControls}
      gearDraft={gearDraft}
      setGearDraft={setGearDraft}
      ddInputFocused={ddInputFocused}
      setDdInputFocused={setDdInputFocused}
      savingGearSettings={savingGearSettings}
      hasUser={hasUser}
      onSaveGear={onSaveGear}
      onCancelGear={onCancelGear}
    />
  )

  return (
    <div>
      <div data-tt-tour-target="dashboardAccountAndDates">
      <TradeFilterBar
        className={DASHBOARD_MOBILE_FILTER_MARGIN_CLASS}
        mobileThreeRowLayout
        accountPickerLayout="dashboard"
        accounts={accounts}
        accountFilter={accountFilter}
        onAccountChange={onAccountChange}
        isPro={isPro}
        copyGroups={copyGroups}
        onAccountPickerOpen={onRequestCopyGroups}
        accountTypeFilter={accountTypeFilter}
        onAccountTypeChange={onAccountTypeChange}
        timeframe={timeframe}
        onTimeframeChange={onTimeframeChange}
        customRangeStart={customRangeStart}
        customRangeEnd={customRangeEnd}
        onCustomRangeApply={onCustomRangeApply}
        selectedDate={selectedDate}
        onSelectedDateChange={onSelectedDateChange}
        publicNextToModes={
          showShareControls ? (
            <button
              type="button"
              onClick={onTogglePublicOnly}
              className={`${DASHBOARD_MOBILE_PUBLIC_BTN_BASE} md:hidden ${
                showPublicOnly
                  ? "border-blue-400 bg-blue-500 text-white hover:bg-blue-600"
                  : "border-white/10 bg-[#0f172a] text-white hover:bg-[#1e293b]"
              }`}
            >
              Public
            </button>
          ) : null
        }
        settingsNextToModes={
          <div className="flex items-stretch justify-center gap-2 md:hidden">
            <PlatformDashboardCalendarButton />
            {gearSettings}
          </div>
        }
        beforeTimeframe={<PlatformDashboardTradesButton />}
        trailing={
          <>
            <Link
              href="/withdrawals"
              data-tt-tour-target="dashboardWithdrawals"
              className="tt-dash-desktop-only h-[34px] shrink-0 rounded-md bg-white/10 px-3 text-sm text-white hover:bg-white/20"
            >
              Withdrawals
            </Link>
            <Link
              href="/calendar"
              data-tt-tour-target="dashboardCalendar"
              className="tt-dash-desktop-only h-[34px] shrink-0 rounded-md bg-white/10 px-3 text-sm text-white hover:bg-white/20"
            >
              Calendar
            </Link>
            {showTradingReportButton && onOpenTradingReport ? (
              <button
                type="button"
                onClick={onOpenTradingReport}
                data-tt-tour-target="dashboardReports"
                className="tt-dash-desktop-only h-[34px] shrink-0 rounded-md bg-white/10 px-3 text-sm text-white hover:bg-white/20"
              >
                Reports
              </button>
            ) : null}
            {showTradingReportButton && onOpenTradingReport ? (
              <button
                type="button"
                onClick={onOpenTradingReport}
                data-tt-tour-target="dashboardReports"
                className={`${DASHBOARD_MOBILE_ACTION_BTN_CLASS} min-w-0 flex-1 md:hidden`}
              >
                Report
              </button>
            ) : null}
            <Link
              href="/withdrawals"
              data-tt-tour-target="dashboardWithdrawals"
              className={`${DASHBOARD_MOBILE_ACTION_BTN_CLASS} min-w-0 flex-1 md:hidden`}
            >
              Withdrawals
            </Link>
            {showShareControls ? (
              <PerformanceShareButton
                onClick={onOpenPerformanceShare}
                size="dashboard"
              />
            ) : null}
            {showShareControls ? (
              <button
                type="button"
                onClick={onTogglePublicOnly}
                className={`hidden md:inline-flex h-[34px] items-center shrink-0 whitespace-nowrap rounded-md px-3 text-sm ${
                  showPublicOnly
                    ? "tt-dash-selected bg-blue-500 text-white hover:bg-blue-600"
                    : "bg-white/10 text-white hover:bg-white/20"
                }`}
              >
                Public Trades
              </button>
            ) : null}

            <div className="hidden md:flex shrink-0 items-center justify-center">
              {gearSettings}
            </div>
          </>
        }
      />
      </div>
      {showPropFirmLink ? (
        <div className="tt-dash-hide-desktop-v1 -mt-1 mb-2 flex justify-end md:justify-start md:mb-3">
          <Link
            href="/analytics/propfirm"
            className="text-xs text-blue-300 transition hover:text-blue-200"
          >
            View Prop Firm Dashboard →
          </Link>
        </div>
      ) : null}
    </div>
  )
}
