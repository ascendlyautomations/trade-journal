"use client"

import PlatformPageHeader, {
  NATIVE_IOS_PAGE_HEADER_ACTION_CLASS,
} from "@/app/components/platform/PlatformPageHeader"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import PlatformDashboardCalendarButton from "@/app/components/platform/PlatformDashboardCalendarButton"
import PlatformDashboardTradesButton from "@/app/components/platform/PlatformDashboardTradesButton"
import { hapticLight } from "@/lib/nativeHaptics"

type NativeIosDashboardActionBarProps = {
  accounts: Array<{ value: string; label: string; accountType?: string | null }>
  accountFilter: string
  onAccountChange: (value: string) => void
  isPro: boolean
  copyGroups: CopyTradingGroup[]
  onOpenQuickInput: () => void
  onOpenFilters: () => void
  onAccountPickerOpen?: () => void
}

/**
 * Native Dashboard header via PlatformPageHeader.
 * Left: Account · Right: Calendar, Trades, Filter
 * `onOpenQuickInput` retained for API compatibility (Add tab / other entry points).
 */
export default function NativeIosDashboardActionBar({
  accounts,
  accountFilter,
  onAccountChange,
  isPro,
  copyGroups,
  onOpenQuickInput: _onOpenQuickInput,
  onOpenFilters,
  onAccountPickerOpen,
}: NativeIosDashboardActionBarProps) {
  return (
    <PlatformPageHeader
      leftContent={
        <div className="min-w-0 w-full max-w-[min(100%,16.5rem)]">
          <TradeAccountPicker
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
        </div>
      }
      rightActions={
        <>
          <PlatformDashboardCalendarButton />
          <PlatformDashboardTradesButton />
          <button
            type="button"
            onClick={() => {
              hapticLight("filters")
              onOpenFilters()
            }}
            aria-label="Filters"
            className={NATIVE_IOS_PAGE_HEADER_ACTION_CLASS}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden
            >
              <line x1="4" x2="4" y1="21" y2="14" />
              <line x1="4" x2="4" y1="10" y2="3" />
              <line x1="12" x2="12" y1="21" y2="12" />
              <line x1="12" x2="12" y1="8" y2="3" />
              <line x1="20" x2="20" y1="21" y2="16" />
              <line x1="20" x2="20" y1="12" y2="3" />
              <line x1="2" x2="6" y1="14" y2="14" />
              <line x1="10" x2="14" y1="8" y2="8" />
              <line x1="18" x2="22" y1="16" y2="16" />
            </svg>
          </button>
        </>
      }
    />
  )
}
