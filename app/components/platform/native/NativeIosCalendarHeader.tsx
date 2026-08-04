"use client"

import CustomSelect from "@/app/components/CustomSelect"
import PlatformPageHeader from "@/app/components/platform/PlatformPageHeader"

/** Compact trigger — fits h-14 native header without growing it. */
const NATIVE_CALENDAR_FILTER_TRIGGER_CLASS =
  "flex h-9 w-full min-w-0 cursor-pointer items-center justify-between rounded-md border border-white/15 bg-white/10 px-2.5 text-left text-[13px] font-medium text-white transition active:bg-white/15 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

export type NativeIosCalendarHeaderProps = {
  accountFilter: string
  onAccountFilterChange: (value: string) => void
  accountOptions: Array<{ value: string; label: string }>
  selectedMode: string
  onModeChange: (value: string) => void
}

/**
 * Native Calendar header — filter bar (All Accounts · All Modes).
 * No title; same filter callbacks as the in-page web controls.
 */
export default function NativeIosCalendarHeader({
  accountFilter,
  onAccountFilterChange,
  accountOptions,
  selectedMode,
  onModeChange,
}: NativeIosCalendarHeaderProps) {
  return (
    <PlatformPageHeader
      leftContent={
        <div className="flex w-full min-w-0 items-center gap-2">
          <CustomSelect
            value={accountFilter}
            onChange={onAccountFilterChange}
            className="min-w-0 flex-1"
            triggerClassName={NATIVE_CALENDAR_FILTER_TRIGGER_CLASS}
            options={[
              { label: "All Accounts", value: "all" },
              ...accountOptions.map(({ value, label }) => ({
                value,
                label,
              })),
            ]}
          />
          <CustomSelect
            value={selectedMode}
            onChange={onModeChange}
            className="min-w-0 flex-1"
            triggerClassName={NATIVE_CALENDAR_FILTER_TRIGGER_CLASS}
            options={[
              { label: "All Modes", value: "all" },
              { label: "Live", value: "live" },
              { label: "Funded", value: "funded" },
              { label: "Eval", value: "eval" },
              { label: "Backtest", value: "backtest" },
            ]}
          />
        </div>
      }
    />
  )
}
