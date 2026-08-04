"use client"

import PlatformPageHeader, {
  NATIVE_IOS_PAGE_HEADER_ACTION_CLASS,
} from "@/app/components/platform/PlatformPageHeader"

/**
 * Native Trades header — title + filter.
 */
export default function NativeIosTradesHeader({
  onOpenFilters,
}: {
  onOpenFilters: () => void
}) {
  return (
    <PlatformPageHeader
      title="Trades"
      rightActions={
        <button
          type="button"
          onClick={onOpenFilters}
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
      }
    />
  )
}
