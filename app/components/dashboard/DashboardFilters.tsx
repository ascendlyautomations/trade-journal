"use client"

import { useState, type Dispatch, type SetStateAction } from "react"
import Link from "next/link"
import TradeFilterBar, {
  type TradeFilterBarProps,
} from "@/app/components/TradeFilterBar"
import Button from "@/app/components/ui/Button"
import PerformanceShareButton from "@/app/components/PerformanceShareButton"
import DashboardGearSettings from "./DashboardGearSettings"
import { DashboardPlanIndicator } from "./DashboardHeader"
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
      <TradeFilterBar
        className={DASHBOARD_MOBILE_FILTER_MARGIN_CLASS}
        mobileThreeRowLayout
        leading={<DashboardPlanIndicator isPro={isPro} />}
        leadingOverlay
        beforeAccountSelect={
          <Button
            type="button"
            variant="primary"
            size="md"
            onClick={onOpenQuickInput}
            className="h-[34px] shrink-0 whitespace-nowrap py-0"
          >
            Quick Trade
          </Button>
        }
        accountSelectAccessory={
          <Button
            type="button"
            variant="primary"
            size="md"
            onClick={onOpenQuickInput}
            aria-label="Quick Trade"
            className="h-9 w-9 shrink-0 p-0 text-base leading-none"
          >
            <span aria-hidden>+</span>
          </Button>
        }
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
            {showTradingReportButton && onOpenTradingReport ? (
              <button
                type="button"
                onClick={onOpenTradingReport}
                className={`${DASHBOARD_MOBILE_ACTION_BTN_CLASS} min-w-0 flex-1 md:hidden`}
              >
                Report
              </button>
            ) : null}
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
                    ? "bg-blue-500 text-white hover:bg-blue-600"
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
      {showPropFirmLink ? (
        <div className="-mt-1 mb-2 flex justify-end md:justify-start md:mb-3">
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
