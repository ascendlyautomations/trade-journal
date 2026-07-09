"use client"

import type { Dispatch, SetStateAction } from "react"
import Link from "next/link"
import TradeFilterBar, {
  type TradeFilterBarProps,
} from "@/app/components/TradeFilterBar"
import PerformanceShareButton from "@/app/components/PerformanceShareButton"
import DashboardGearSettings from "./DashboardGearSettings"
import { DashboardPlanIndicator } from "./DashboardHeader"
import {
  DASHBOARD_MOBILE_ACTION_BTN_CLASS,
  DASHBOARD_MOBILE_PUBLIC_BTN_BASE,
} from "./dashboardHeaderMobileUi"
import type { GearDraftState } from "./dashboardGearTypes"

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
}: DashboardFiltersProps) {
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
        className="mt-2 mb-2.5 md:mt-2.5 md:mb-4"
        mobileThreeRowLayout
        leading={<DashboardPlanIndicator isPro={isPro} />}
        leadingOverlay
        accounts={accounts}
        accountFilter={accountFilter}
        onAccountChange={onAccountChange}
        isPro={isPro}
        copyGroups={copyGroups}
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
                ? "border-emerald-400 bg-emerald-500 text-white hover:bg-emerald-600"
                : "border-white/10 bg-[#0f172a] text-white hover:bg-[#1e293b]"
            }`}
          >
            Public
          </button>
          ) : null
        }
        settingsNextToModes={<div className="md:hidden">{gearSettings}</div>}
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
              className={`hidden md:inline-flex shrink-0 whitespace-nowrap rounded-md px-3 py-2 text-sm ${
                showPublicOnly
                  ? "bg-emerald-500 text-white hover:bg-emerald-600"
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
        <div className="-mt-1 mb-3 flex justify-end md:justify-start md:mb-4">
          <Link
            href="/analytics/propfirm"
            className="text-xs text-blue-300/70 transition hover:text-blue-200"
          >
            View Prop Firm Dashboard →
          </Link>
        </div>
      ) : null}
    </div>
  )
}
