"use client"

import type { Dispatch, SetStateAction } from "react"
import TradeFilterBar, {
  type TradeFilterBarProps,
} from "@/app/components/TradeFilterBar"
import DashboardGearSettings from "./DashboardGearSettings"
import type { GearDraftState } from "./dashboardGearTypes"

export type DashboardHeaderProps = {
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
  isPro: boolean
  showFreePlanAccountBanner: boolean
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
}

export default function DashboardHeader({
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
  isPro,
  showFreePlanAccountBanner,
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
}: DashboardHeaderProps) {
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
    <div className="relative z-50 mx-auto w-full max-w-[1600px] px-4 md:px-6">
      <TradeFilterBar
        className="mt-2.5 mb-0"
        mobileThreeRowLayout
        accounts={accounts}
        accountFilter={accountFilter}
        onAccountChange={onAccountChange}
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
          <button
            type="button"
            onClick={onTogglePublicOnly}
            className={`h-[34px] w-full whitespace-nowrap rounded-md border px-4 py-2 text-sm md:h-[34px] md:w-auto md:px-2 md:py-1 md:text-xs md:hidden ${
              showPublicOnly
                ? "border-emerald-400 bg-emerald-500 text-white hover:bg-emerald-600"
                : "border-white/10 bg-[#0f172a] text-white hover:bg-[#1e293b]"
            }`}
          >
            Public
          </button>
        }
        settingsNextToModes={<div className="md:hidden">{gearSettings}</div>}
        trailing={
          <>
            <button
              type="button"
              onClick={onOpenPerformanceShare}
              className="inline-flex h-[34px] w-full items-center justify-center whitespace-nowrap rounded-md bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20 md:hidden"
              title="Share performance"
              aria-label="Share performance"
            >
              📤 Share
            </button>
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
            <button
              type="button"
              onClick={onOpenPerformanceShare}
              className="hidden md:inline-flex h-[34px] shrink-0 items-center whitespace-nowrap rounded-md bg-white/10 px-3 py-1 text-sm text-white hover:bg-white/20"
              title="Share performance"
              aria-label="Share performance"
            >
              📤 Share
            </button>

            <div className="hidden md:flex shrink-0 items-center justify-center">
              {gearSettings}
            </div>
          </>
        }
      />

      <div className="mt-1 mb-2 text-left text-sm text-white/60">
        Plan:{" "}
        <span
          className={`font-medium ${isPro ? "text-green-400" : "text-gray-400"}`}
        >
          {isPro ? "Pro" : "Free"}
        </span>
      </div>

      {showFreePlanAccountBanner ? (
        <div className="mb-4 rounded border border-yellow-500/20 bg-yellow-500/10 p-3 md:p-4">
          <p className="text-xs md:text-sm text-yellow-300">
            Free plan: 1 account limit. Upgrade for unlimited accounts.
          </p>
        </div>
      ) : null}
    </div>
  )
}
